#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
environment="${DEPLOYMENT_ENV:-testnet}"
if [[ "$environment" == "mainnet" ]]; then
    # shellcheck source=scripts/lib/mainnet-common.sh
    source "$SCRIPT_DIR/lib/mainnet-common.sh"
    load_mainnet_env
    assert_mainnets
    ensure_solana_mainnet_deployment_file
    [[ "$(json_get '.evmOft.sourceVerification')" == "PASS" ]] || die "Verify mainnet EVM source before authority handoff"
    [[ "$(json_get '.solanaAdapter.sourceVerification.localHashMatch // false')" == "true" ]] || \
        die "Verify the deployed mainnet Solana executable hash before authority handoff"
else
    # shellcheck source=scripts/lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
    load_testnet_env
    assert_public_testnets
    ensure_solana_deployment_file
fi

for command in jq pnpm rg solana; do require_cmd "$command"; done
DEPLOYMENT_ENV="$environment" pnpm ts-node --transpile-only scripts/create-admins.ts

safe="$(json_get '.administration.robinhoodSafe.address // empty')"
vault="$(json_get '.administration.solanaSquads.vault // empty')"
program_id="$(json_get '.solanaAdapter.programId // empty')"
[[ -n "$safe" && -n "$vault" && -n "$program_id" ]] || die "Admin containers or OFT program are missing"

wire_output="$(mktemp "${TMPDIR:-/tmp}/stonks-admin-delegates.XXXXXX")"
owner_output="$(mktemp "${TMPDIR:-/tmp}/stonks-admin-owners.XXXXXX")"
ADMIN_HANDOFF=1 EVM_ADMIN_SAFE="$safe" SOLANA_ADMIN_VAULT="$vault" DEPLOYMENT_ENV="$environment" \
    pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts --ci 2>&1 | tee "$wire_output"
ADMIN_HANDOFF=1 EVM_ADMIN_SAFE="$safe" SOLANA_ADMIN_VAULT="$vault" DEPLOYMENT_ENV="$environment" \
    pnpm hardhat lz:ownable:transfer-ownership --oapp-config layerzero.config.ts --ci 2>&1 | tee "$owner_output"

ADMIN_HANDOFF=1 EVM_ADMIN_SAFE="$safe" SOLANA_ADMIN_VAULT="$vault" DEPLOYMENT_ENV="$environment" \
    pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts --assert
ADMIN_HANDOFF=1 EVM_ADMIN_SAFE="$safe" SOLANA_ADMIN_VAULT="$vault" DEPLOYMENT_ENV="$environment" \
    pnpm hardhat lz:ownable:transfer-ownership --oapp-config layerzero.config.ts --assert

program_json="$(solana program show "$program_id" --url "$SOLANA_RPC_URL" \
    --keypair "$SOLANA_KEYPAIR_PATH" --output json)"
current_authority="$(jq -er '.authority' <<<"$program_json")"
if [[ "$current_authority" != "$vault" ]]; then
    [[ "$current_authority" == "$(json_get '.wallets.solana')" ]] || die "Unexpected upgrade authority $current_authority"
    upgrade_output="$(solana program set-upgrade-authority "$program_id" --url "$SOLANA_RPC_URL" \
        --keypair "$SOLANA_KEYPAIR_PATH" --upgrade-authority "$SOLANA_KEYPAIR_PATH" \
        --new-upgrade-authority "$vault" --skip-new-upgrade-authority-signer-check \
        --commitment confirmed --output json-compact)"
    printf '%s\n' "$upgrade_output"
    upgrade_signature="$(jq -r '.signature // empty' <<<"$upgrade_output")"
else
    upgrade_signature=""
fi

verified_authority="$(solana program show "$program_id" --url "$SOLANA_RPC_URL" \
    --keypair "$SOLANA_KEYPAIR_PATH" --output json | jq -er '.authority')"
[[ "$verified_authority" == "$vault" ]] || die "Program authority handoff did not persist"
DEPLOYMENT_ENV="$environment" CHECKPOINT_FILE="$CHECKPOINT_FILE" pnpm ts-node --transpile-only scripts/inspect-evm-oft.ts

handoff_transactions="$(
    {
        rg -o '(0x[0-9a-fA-F]{64}|[1-9A-HJ-NP-Za-km-z]{64,100})' "$wire_output" "$owner_output" || true
    } | sed 's/^[^:]*://' | sort -u | jq -Rsc 'split("\n") | map(select(length>0))'
)"
if [[ -n "$upgrade_signature" ]]; then
    handoff_transactions="$(jq -c --arg sig "$upgrade_signature" '. + [$sig] | unique' <<<"$handoff_transactions")"
fi
checkpoint_arg \
    '.solanaAdapter.admin=$vault | .solanaAdapter.delegate=$vault | .solanaAdapter.programUpgradeAuthority=$vault |
     .solanaAdapter.authorityHandoffTransactions=((.solanaAdapter.authorityHandoffTransactions // []) + $txs | unique) |
     .evmOft.owner=$safe | .evmOft.delegate=$safe |
     .evmOft.authorityHandoffTransactions=((.evmOft.authorityHandoffTransactions // []) + $txs | unique)' \
    --arg vault "$vault" --arg safe "$safe" --argjson txs "$handoff_transactions"

post_handoff_output="$(mktemp "${TMPDIR:-/tmp}/stonks-admin-readback.XXXXXX")"
ADMIN_HANDOFF=1 EVM_ADMIN_SAFE="$safe" SOLANA_ADMIN_VAULT="$vault" DEPLOYMENT_ENV="$environment" \
    pnpm hardhat lz:oapp:config:get --oapp-config layerzero.config.ts 2>&1 | tee "$post_handoff_output"
post_handoff_raw="$(<"$post_handoff_output")"
config_tmp="$(mktemp "$CONFIG_EVIDENCE_FILE.tmp.XXXXXX")"
jq --arg safe "$safe" --arg vault "$vault" --arg raw "$post_handoff_raw" \
    '.applicationReadback.evmOft.owner=$safe |
     .applicationReadback.evmOft.delegate=$safe |
     .applicationReadback.solanaOftStore.admin=$vault |
     .applicationReadback.solanaOftStore.delegate=$vault |
     .applicationReadback.postHandoffRawConfigGetOutput=$raw |
     .applicationReadback.authorityHandoffAsserted=true |
     .applicationReadback.authorityHandoffReadAt=(now|todateiso8601) |
     .updatedAt=(now|todateiso8601)' "$CONFIG_EVIDENCE_FILE" >"$config_tmp"
mv "$config_tmp" "$CONFIG_EVIDENCE_FILE"

note "PASS: OApp owners/delegates and Solana program upgrade authority are held by the protected admin containers"
