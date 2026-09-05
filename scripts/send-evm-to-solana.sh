#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
environment="${DEPLOYMENT_ENV:-testnet}"
if [[ "$environment" == "mainnet" ]]; then
    # shellcheck source=scripts/lib/mainnet-common.sh
    source "$SCRIPT_DIR/lib/mainnet-common.sh"
else
    # shellcheck source=scripts/lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
fi

for command in jq pnpm rg; do require_cmd "$command"; done
if [[ "$environment" == "mainnet" ]]; then
    load_mainnet_env
    assert_mainnets
    ensure_solana_mainnet_deployment_file
else
    load_testnet_env
    assert_public_testnets
    ensure_solana_deployment_file
fi

[[ -n "$(json_get '.evmOft.address // empty')" ]] || die "EVM OFT is not deployed"
amount="${1:-${E2S_AMOUNT:-400}}"
[[ "$amount" =~ ^[0-9]+([.][0-9]{1,6})?$ ]] || die "Amount must be representable at shared decimals (<=6 decimal places)"
amount_local_raw="$(decimal_to_units "$amount" 18)"
amount_shared_raw="$(decimal_to_units "$amount" 6)"
destination="$(json_get '.wallets.solana')"

before="$(DEPLOYMENT_ENV="$environment" pnpm ts-node --transpile-only scripts/snapshot-balances.ts)"
output="$(mktemp "${TMPDIR:-/tmp}/stonks-send-evm.XXXXXX")"
set +e
CI=1 pnpm hardhat lz:oft:send \
    --src-eid "$ROBINHOOD_EID" \
    --dst-eid "$SOLANA_EID" \
    --to "$destination" \
    --amount "$amount" >"$output" 2>&1
status=$?
set -e
cat "$output"
((status == 0)) || die "Robinhood to Solana OFT send failed"

source_tx="$(rg -o 'tx/0x[0-9a-fA-F]{64}' "$output" | head -1 | cut -d/ -f2 || true)"
[[ -n "$source_tx" ]] || die "Could not extract EVM source transaction from send output"
native_fee="$(rg -o 'LayerZero native fee: [0-9]+' "$output" | tail -1 | awk '{print $4}' || true)"
[[ -n "$native_fee" ]] || die "Could not extract the quoted LayerZero native fee"
message_filter='.messages += [{direction:"EVM_TO_SOLANA",amountUi:$amount,amountLocalRaw:$local,localDecimals:18,amountSharedRaw:$shared,sharedDecimals:6,destinationAddress:$destination,quotedNativeFee:$fee,quotedNativeFeeUnit:"wei",sourceEid:$sourceEid,destinationEid:$destinationEid,sourceTransaction:$tx,destinationTransaction:null,guid:null,status:"SUBMITTED",before:$before}]'
if [[ "$environment" == "mainnet" ]]; then
    message_filter='.canary.status="IN_PROGRESS" | .canary.messages += [{direction:"EVM_TO_SOLANA",amountUi:$amount,amountLocalRaw:$local,localDecimals:18,amountSharedRaw:$shared,sharedDecimals:6,destinationAddress:$destination,quotedNativeFee:$fee,quotedNativeFeeUnit:"wei",sourceEid:$sourceEid,destinationEid:$destinationEid,sourceTransaction:$tx,destinationTransaction:null,guid:null,status:"SUBMITTED",before:$before}]'
fi
checkpoint_arg "$message_filter" \
    --arg amount "$amount" --arg local "$amount_local_raw" --arg shared "$amount_shared_raw" \
    --arg destination "$destination" --arg fee "$native_fee" --arg tx "$source_tx" --argjson before "$before" \
    --argjson sourceEid "$ROBINHOOD_EID" --argjson destinationEid "$SOLANA_EID"

DEPLOYMENT_ENV="$environment" pnpm ts-node --transpile-only scripts/capture-layerzero-message.ts --tx "$source_tx"
after="$(DEPLOYMENT_ENV="$environment" pnpm ts-node --transpile-only scripts/snapshot-balances.ts)"
after_filter='(.messages[] | select(.sourceTransaction==$tx) | .after) = $after'
[[ "$environment" == "mainnet" ]] && after_filter='(.canary.messages[] | select(.sourceTransaction==$tx) | .after) = $after'
checkpoint_arg "$after_filter" \
    --arg tx "$source_tx" --argjson after "$after"
note "PASS: Robinhood -> Solana delivered; source transaction $source_tx"
