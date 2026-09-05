#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

for command in jq pnpm rg; do require_cmd "$command"; done
load_testnet_env
assert_public_testnets
ensure_solana_deployment_file

[[ -n "$(json_get '.evmOft.address // empty')" ]] || die "EVM OFT is not deployed"
amount="${1:-${E2S_AMOUNT:-400}}"
[[ "$amount" =~ ^[0-9]+([.][0-9]{1,6})?$ ]] || die "Amount must be representable at shared decimals (<=6 decimal places)"
amount_local_raw="$(decimal_to_units "$amount" 18)"
amount_shared_raw="$(decimal_to_units "$amount" 6)"
destination="$(json_get '.wallets.solana')"

before="$(pnpm ts-node --transpile-only scripts/snapshot-balances.ts)"
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
checkpoint_arg \
    '.messages += [{direction:"EVM_TO_SOLANA",amountUi:$amount,amountLocalRaw:$local,localDecimals:18,amountSharedRaw:$shared,sharedDecimals:6,destinationAddress:$destination,quotedNativeFee:$fee,quotedNativeFeeUnit:"wei",sourceEid:40451,destinationEid:40168,sourceTransaction:$tx,destinationTransaction:null,guid:null,status:"SUBMITTED",before:$before}]' \
    --arg amount "$amount" --arg local "$amount_local_raw" --arg shared "$amount_shared_raw" \
    --arg destination "$destination" --arg fee "$native_fee" --arg tx "$source_tx" --argjson before "$before"

pnpm ts-node --transpile-only scripts/capture-layerzero-message.ts --tx "$source_tx"
after="$(pnpm ts-node --transpile-only scripts/snapshot-balances.ts)"
checkpoint_arg \
    '(.messages[] | select(.sourceTransaction==$tx) | .after) = $after' \
    --arg tx "$source_tx" --argjson after "$after"
note "PASS: Robinhood -> Solana delivered; source transaction $source_tx"
