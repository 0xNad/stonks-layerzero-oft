#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/mainnet-common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/mainnet-common.sh"

for command in curl jq pnpm rg shasum solana solana-keygen; do require_cmd "$command"; done
load_mainnet_env
assert_mainnets

deployer="$(json_get '.wallets.solana')"
[[ "$(solana-keygen pubkey "$SOLANA_KEYPAIR_PATH")" == "$deployer" ]] || die "Mainnet Solana key does not match checkpoint"

mint_result="$(solana_rpc getAccountInfo "$(jq -nc --arg mint "$STONKS_MINT" '[$mint,{encoding:"jsonParsed",commitment:"finalized"}]')")"
mint_owner="$(jq -er '.result.value.owner' <<<"$mint_result")"
decimals="$(jq -er '.result.value.data.parsed.info.decimals' <<<"$mint_result")"
supply="$(jq -er '.result.value.data.parsed.info.supply' <<<"$mint_result")"
mint_authority="$(jq -r '.result.value.data.parsed.info.mintAuthority' <<<"$mint_result")"
freeze_authority="$(jq -r '.result.value.data.parsed.info.freezeAuthority' <<<"$mint_result")"
observed_slot="$(jq -er '.result.context.slot' <<<"$mint_result")"
[[ "$mint_owner" == "$TOKEN_PROGRAM_ID" ]] || die "STONKS is not owned by classic SPL Token"
[[ "$decimals" == "9" ]] || die "STONKS decimals changed to $decimals"
[[ "$mint_authority" == "null" && "$freeze_authority" == "null" ]] || die "STONKS authority state is unsafe"
checkpoint_arg '.token.supplyRawBeforeBridge=$supply | .token.observedSlot=$slot' --arg supply "$supply" --argjson slot "$observed_slot"

program_keypair="${OFT_PROGRAM_KEYPAIR_PATH:-.mainnet-secrets/oft-program-keypair.json}"
require_file "$program_keypair"
[[ "$(stat -f '%Lp' "$program_keypair")" == "600" ]] || die "$program_keypair must have mode 600"
program_id="$(solana-keygen pubkey "$program_keypair")"
[[ "$program_id" == "$(json_get '.solanaAdapter.programId')" ]] || die "Program ID does not match protected checkpoint"

if solana program show "$program_id" --url "$SOLANA_RPC_URL" --keypair "$SOLANA_KEYPAIR_PATH" >/dev/null 2>&1; then
    minimum_lamports=500000000
else
    minimum_lamports=3800000000
fi
current_lamports="$(solana_balance_lamports "$deployer")"
[[ "$current_lamports" -ge "$minimum_lamports" ]] || \
    die "Mainnet Solana deployer has $current_lamports lamports; requires at least $minimum_lamports"

buffer_keypair="${OFT_PROGRAM_BUFFER_KEYPAIR_PATH:-.mainnet-secrets/oft-program-buffer.json}"
if [[ ! -f "$buffer_keypair" ]]; then
    solana-keygen new --no-bip39-passphrase --silent --outfile "$buffer_keypair" >/dev/null
    chmod 600 "$buffer_keypair"
fi

binary="${OFT_PROGRAM_BINARY:-$ROOT_DIR/target/verifiable/oft.so}"
[[ -f "$binary" ]] || binary="$ROOT_DIR/target/deploy/oft.so"
require_file "$binary"
program_max_len="${OFT_PROGRAM_MAX_LEN:-600000}"
[[ "$(stat -f '%z' "$binary")" -le "$program_max_len" ]] || die "OFT binary exceeds configured program max length"
binary_size="$(stat -f '%z' "$binary")"
binary_sha="$(shasum -a 256 "$binary" | awk '{print $1}')"
checkpoint_arg '.solanaAdapter.programBinaryBytes=$size | .solanaAdapter.programBinarySha256=$sha' \
    --argjson size "$binary_size" --arg sha "$binary_sha"

# Send upgradeable-loader write transactions directly to the TPU by default.
# Set SOLANA_DEPLOY_USE_RPC=1 only when using a private RPC that supports the
# sustained transaction rate required by a program upload.
deploy_transport=(--use-quic)
if [[ "${SOLANA_DEPLOY_USE_RPC:-0}" == "1" ]]; then
    deploy_transport=(--use-rpc)
fi

if ! solana program show "$program_id" --url "$SOLANA_RPC_URL" --keypair "$SOLANA_KEYPAIR_PATH" >/dev/null 2>&1; then
    output="$(mktemp "${TMPDIR:-/tmp}/stonks-solana-mainnet-deploy.XXXXXX")"
    set +e
    solana program deploy --url "$SOLANA_RPC_URL" --keypair "$SOLANA_KEYPAIR_PATH" \
        --program-id "$program_keypair" --buffer "$buffer_keypair" --max-len "$program_max_len" \
        "${deploy_transport[@]}" --commitment confirmed \
        --with-compute-unit-price 1 --output json-compact "$binary" >"$output" 2>&1
    status=$?
    set -e
    cat "$output"
    ((status == 0)) || die "Mainnet OFT program deployment failed"
    signature="$(rg --no-filename -o '"(signature|transactionSignature)"[[:space:]]*:[[:space:]]*"[1-9A-HJ-NP-Za-km-z]{64,100}"' "$output" | tail -1 | sed -E 's/^.*"([1-9A-HJ-NP-Za-km-z]{64,100})"$/\1/' || true)"
    [[ -z "$signature" ]] || checkpoint_arg '.solanaAdapter.programDeploymentTransactions += [$sig]' --arg sig "$signature"
fi

program_json="$(solana program show "$program_id" --url "$SOLANA_RPC_URL" --output json)"
upgrade_authority="$(jq -er '.authority' <<<"$program_json")"
[[ "$upgrade_authority" == "$deployer" || "$upgrade_authority" == "$(json_get '.administration.solanaSquads.vault // empty')" ]] || \
    die "Unexpected program upgrade authority $upgrade_authority"
checkpoint_arg '.solanaAdapter.programUpgradeAuthority=$authority' --arg authority "$upgrade_authority"

adapter_file="$ROOT_DIR/deployments/solana-mainnet/OFT.json"
if [[ -z "$(json_get '.solanaAdapter.oftStore // empty')" ]]; then
    if [[ ! -f "$adapter_file" ]]; then
        printf 'y\n' | CI=1 pnpm hardhat lz:oft-adapter:solana:create --eid "$SOLANA_EID" --program-id "$program_id" \
            --mint "$STONKS_MINT" --token-program "$TOKEN_PROGRAM_ID"
    fi
    require_file "$adapter_file"
    [[ "$(jq -r '.programId' "$adapter_file")" == "$program_id" ]] || die "Wrong program in adapter artifact"
    [[ "$(jq -r '.mint' "$adapter_file")" == "$STONKS_MINT" ]] || die "Wrong mint in adapter artifact"
    checkpoint_arg '.solanaAdapter.oftStore=$store | .solanaAdapter.escrow=$escrow' \
        --arg store "$(jq -r '.oftStore' "$adapter_file")" --arg escrow "$(jq -r '.escrow' "$adapter_file")"
fi

note "PASS: mainnet Solana OFT Adapter program=$program_id store=$(json_get '.solanaAdapter.oftStore')"
