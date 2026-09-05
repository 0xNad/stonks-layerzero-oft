#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

for command in jq pnpm rg solana solana-keygen solana-verify; do require_cmd "$command"; done
load_testnet_env
assert_public_testnets

mint="$(json_get '.token.mint // empty')"
[[ -n "$mint" ]] || die "Create tSTONKS first with scripts/create-solana-token.sh"
[[ "$(json_get '.token.mintAuthority')" == "null" ]] || die "Mint authority must be revoked before adapter creation"
[[ "$(json_get '.token.freezeAuthority')" == "null" ]] || die "Freeze authority must be revoked before adapter creation"

program_keypair="${OFT_PROGRAM_KEYPAIR_PATH:-.testnet-secrets/oft-program-keypair.json}"
require_file "$program_keypair"
[[ "$(stat -f '%Lp' "$program_keypair")" == "600" ]] || die "$program_keypair must have mode 600"
program_id="$(solana-keygen pubkey "$program_keypair")"
buffer_keypair="${OFT_PROGRAM_BUFFER_KEYPAIR_PATH:-.testnet-secrets/oft-program-buffer.json}"
if [[ ! -f "$buffer_keypair" ]]; then
    solana-keygen new --no-bip39-passphrase --silent --outfile "$buffer_keypair" >/dev/null
    chmod 600 "$buffer_keypair"
fi
[[ "$(stat -f '%Lp' "$buffer_keypair")" == "600" ]] || die "$buffer_keypair must have mode 600"
buffer_id="$(solana-keygen pubkey "$buffer_keypair")"

checkpoint_program="$(json_get '.solanaAdapter.programId // empty')"
if [[ -n "$checkpoint_program" && "$checkpoint_program" != "$program_id" ]]; then
    die "Protected program keypair $program_id does not match checkpoint $checkpoint_program"
fi
checkpoint_arg '.solanaAdapter.programId = $program' --arg program "$program_id"

binary="${OFT_PROGRAM_BINARY:-$ROOT_DIR/target/verifiable/oft.so}"
[[ -f "$binary" ]] || binary="$ROOT_DIR/target/deploy/oft.so"
require_file "$binary"
program_max_len="${OFT_PROGRAM_MAX_LEN:-600000}"
[[ "$(stat -f '%z' "$binary")" -le "$program_max_len" ]] || die "OFT binary exceeds configured program max length"

# Send upgradeable-loader write transactions directly to the TPU by default.
# Public RPC submission is too aggressively rate-limited for a program upload.
deploy_transport=(--use-quic)
if [[ "${SOLANA_DEPLOY_USE_RPC:-0}" == "1" ]]; then
    deploy_transport=(--use-rpc)
fi

if ! solana program show "$program_id" --url "$SOLANA_RPC_URL" \
    --keypair "$SOLANA_KEYPAIR_PATH" >/dev/null 2>&1; then
    lamports="$(solana_balance_lamports "$(json_get '.wallets.solana')")"
    rent_sol="$(solana rent "$(stat -f '%z' "$binary")" --url "$SOLANA_RPC_URL" | awk '{print $3}')"
    note "Deploying OFT program $program_id ($rent_sol SOL rent estimate; payer has $lamports lamports)..."
    deploy_output="$(mktemp "${TMPDIR:-/tmp}/stonks-solana-program-deploy.XXXXXX")"
    set +e
    solana program deploy \
        --url "$SOLANA_RPC_URL" \
        --keypair "$SOLANA_KEYPAIR_PATH" \
        --program-id "$program_keypair" \
        --buffer "$buffer_keypair" \
        --max-len "$program_max_len" \
        "${deploy_transport[@]}" \
        --commitment confirmed \
        --with-compute-unit-price 1 \
        --output json-compact \
        "$binary" >"$deploy_output" 2>&1
    deploy_status=$?
    set -e
    cat "$deploy_output"
    ((deploy_status == 0)) || die "Solana OFT program deployment failed"
    deploy_signature="$(rg --no-filename -o '"(signature|transactionSignature)"[[:space:]]*:[[:space:]]*"[1-9A-HJ-NP-Za-km-z]{64,100}"' \
        "$deploy_output" | tail -1 | sed -E 's/^.*"([1-9A-HJ-NP-Za-km-z]{64,100})"$/\1/' || true)"
    if [[ -n "$deploy_signature" ]]; then
        checkpoint_arg '.solanaAdapter.programDeploymentTransactions += [$sig]' --arg sig "$deploy_signature"
    fi
fi

solana program show "$program_id" --url "$SOLANA_RPC_URL" \
    --keypair "$SOLANA_KEYPAIR_PATH" >/dev/null || die "OFT program is not deployed"

# If a deterministic verifier build is present, make it the deployed test
# binary before any pathway is wired. A native Anchor build can legitimately
# differ even from identical source and must not be accepted as reproducible.
local_hash="$(solana-verify get-executable-hash "$binary" | tr -d '[:space:]')"
onchain_hash="$(solana-verify get-program-hash -u "$SOLANA_RPC_URL" "$program_id" | tr -d '[:space:]')"
if [[ "$local_hash" != "$onchain_hash" ]]; then
    current_authority="$(solana program show "$program_id" --url "$SOLANA_RPC_URL" \
        --keypair "$SOLANA_KEYPAIR_PATH" --output json | jq -er '.authority')"
    [[ "$current_authority" == "$(json_get '.wallets.solana')" ]] || \
        die "Deterministic binary differs, but deployer no longer holds program upgrade authority"
    note "Upgrading Devnet OFT program to the deterministic verifier build..."
    upgrade_output="$(mktemp "${TMPDIR:-/tmp}/stonks-solana-program-upgrade.XXXXXX")"
    set +e
    solana program deploy \
        --url "$SOLANA_RPC_URL" \
        --keypair "$SOLANA_KEYPAIR_PATH" \
        --program-id "$program_keypair" \
        --buffer "$buffer_keypair" \
        "${deploy_transport[@]}" \
        --commitment confirmed \
        --with-compute-unit-price 1 \
        --output json-compact \
        "$binary" >"$upgrade_output" 2>&1
    upgrade_status=$?
    set -e
    cat "$upgrade_output"
    ((upgrade_status == 0)) || die "Deterministic Solana OFT program upgrade failed"
    upgrade_signature="$(rg --no-filename -o '"(signature|transactionSignature)"[[:space:]]*:[[:space:]]*"[1-9A-HJ-NP-Za-km-z]{64,100}"' \
        "$upgrade_output" | tail -1 | sed -E 's/^.*"([1-9A-HJ-NP-Za-km-z]{64,100})"$/\1/' || true)"
    [[ -z "$upgrade_signature" ]] || checkpoint_arg \
        '.solanaAdapter.programDeploymentTransactions += [$sig] | .solanaAdapter.deterministicUpgradeTransaction=$sig' \
        --arg sig "$upgrade_signature"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        onchain_hash="$(solana-verify get-program-hash -u "$SOLANA_RPC_URL" "$program_id" | tr -d '[:space:]')"
        [[ "$local_hash" == "$onchain_hash" ]] && break
        sleep 2
    done
    [[ "$local_hash" == "$onchain_hash" ]] || die "Deployed program still differs from deterministic binary after upgrade"
fi

adapter_file="$ROOT_DIR/deployments/solana-testnet/OFT.json"
oft_store="$(json_get '.solanaAdapter.oftStore // empty')"
if [[ -z "$oft_store" ]]; then
    if [[ -f "$adapter_file" ]]; then
        [[ "$(jq -r '.programId' "$adapter_file")" == "$program_id" ]] || \
            die "Existing adapter file belongs to a different program; use RESET=1 explicitly"
        [[ "$(jq -r '.mint' "$adapter_file")" == "$mint" ]] || \
            die "Existing adapter file belongs to a different mint; use RESET=1 explicitly"
    else
        adapter_output="$(mktemp "${TMPDIR:-/tmp}/stonks-solana-adapter-create.XXXXXX")"
        set +e
        printf 'y\n' | CI=1 pnpm hardhat lz:oft-adapter:solana:create \
            --eid "$SOLANA_EID" \
            --program-id "$program_id" \
            --mint "$mint" \
            --token-program "$TOKEN_PROGRAM_ID" >"$adapter_output" 2>&1
        adapter_status=$?
        set -e
        cat "$adapter_output"
        ((adapter_status == 0)) || die "Solana OFT Adapter creation failed"
        require_file "$adapter_file"
    fi

    [[ -z "$(jq -r '.mintAuthority // empty' "$adapter_file")" ]] || \
        die "Adapter evidence unexpectedly records a mint authority"
    create_signature="${adapter_output:+$(rg -o 'tx/[1-9A-HJ-NP-Za-km-z]{64,100}' "$adapter_output" 2>/dev/null | \
        tail -1 | cut -d/ -f2 || true)}"
    checkpoint_arg \
        '.solanaAdapter.programId=$program | .solanaAdapter.oftStore=$store | .solanaAdapter.escrow=$escrow | .solanaAdapter.createTransaction=($tx | if .=="" then null else . end)' \
        --arg program "$program_id" \
        --arg store "$(jq -r '.oftStore' "$adapter_file")" \
        --arg escrow "$(jq -r '.escrow' "$adapter_file")" \
        --arg tx "$create_signature"
fi

checkpoint_arg '.solanaAdapter.uploadBuffer = $buffer' --arg buffer "$buffer_id"
note "PASS: OFT program=$program_id store=$(json_get '.solanaAdapter.oftStore') escrow=$(json_get '.solanaAdapter.escrow')"
