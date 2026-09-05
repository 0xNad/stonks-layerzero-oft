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
amount="${1:-${S2E_AMOUNT:-1000}}"
[[ "$amount" =~ ^[0-9]+([.][0-9]{1,6})?$ ]] || die "Amount must be representable at shared decimals (<=6 decimal places)"
amount_local_raw="$(decimal_to_units "$amount" 9)"
amount_shared_raw="$(decimal_to_units "$amount" 6)"
destination="$(json_get '.wallets.evm')"

before="$(DEPLOYMENT_ENV="$environment" pnpm ts-node --transpile-only scripts/snapshot-balances.ts)"
output="$(mktemp "${TMPDIR:-/tmp}/stonks-send-solana.XXXXXX")"
set +e
CI=1 pnpm hardhat lz:oft:send \
    --src-eid "$SOLANA_EID" \
    --dst-eid "$ROBINHOOD_EID" \
    --to "$destination" \
    --amount "$amount" \
    --token-program "$TOKEN_PROGRAM_ID" >"$output" 2>&1
status=$?
set -e
cat "$output"
((status == 0)) || die "Solana to Robinhood OFT send failed"

source_tx="$(rg -o 'tx/[1-9A-HJ-NP-Za-km-z]{64,100}' "$output" | head -1 | cut -d/ -f2 || true)"
[[ -n "$source_tx" ]] || die "Could not extract Solana source transaction from send output"
native_fee="$(rg -o 'LayerZero native fee: [0-9]+' "$output" | tail -1 | awk '{print $4}' || true)"
[[ -n "$native_fee" ]] || die "Could not extract the quoted LayerZero native fee"
message_filter='.messages += [{direction:"SOLANA_TO_EVM",amountUi:$amount,amountLocalRaw:$local,localDecimals:9,amountSharedRaw:$shared,sharedDecimals:6,destinationAddress:$destination,quotedNativeFee:$fee,quotedNativeFeeUnit:"lamports",sourceEid:$sourceEid,destinationEid:$destinationEid,sourceTransaction:$tx,destinationTransaction:null,guid:null,status:"SUBMITTED",before:$before}]'
if [[ "$environment" == "mainnet" ]]; then
    message_filter='.canary.status="IN_PROGRESS" | .canary.messages += [{direction:"SOLANA_TO_EVM",amountUi:$amount,amountLocalRaw:$local,localDecimals:9,amountSharedRaw:$shared,sharedDecimals:6,destinationAddress:$destination,quotedNativeFee:$fee,quotedNativeFeeUnit:"lamports",sourceEid:$sourceEid,destinationEid:$destinationEid,sourceTransaction:$tx,destinationTransaction:null,guid:null,status:"SUBMITTED",before:$before}]'
fi
checkpoint_arg "$message_filter" \
    --arg amount "$amount" --arg local "$amount_local_raw" --arg shared "$amount_shared_raw" \
    --arg destination "$destination" --arg fee "$native_fee" --arg tx "$source_tx" --argjson before "$before" \
    --argjson sourceEid "$SOLANA_EID" --argjson destinationEid "$ROBINHOOD_EID"

DEPLOYMENT_ENV="$environment" pnpm ts-node --transpile-only scripts/capture-layerzero-message.ts --tx "$source_tx"
after="$(DEPLOYMENT_ENV="$environment" pnpm ts-node --transpile-only scripts/snapshot-balances.ts)"
after_filter='(.messages[] | select(.sourceTransaction==$tx) | .after) = $after'
[[ "$environment" == "mainnet" ]] && after_filter='(.canary.messages[] | select(.sourceTransaction==$tx) | .after) = $after'
checkpoint_arg "$after_filter" \
    --arg tx "$source_tx" --argjson after "$after"
note "PASS: Solana -> Robinhood delivered; source transaction $source_tx"
