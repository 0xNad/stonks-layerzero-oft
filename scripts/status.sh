#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

for command in curl jq node; do require_cmd "$command"; done
load_testnet_env
assert_public_testnets

solana_address="$(json_get '.wallets.solana')"
evm_address="$(json_get '.wallets.evm')"
solana_lamports="$(solana_balance_lamports "$solana_address")"
evm_wei="$(evm_balance_wei "$evm_address")"

jq --arg sol "$solana_lamports" --arg evm "$evm_wei" '{
  status,
  networkPair,
  wallets,
  liveGas: {solanaLamports:$sol, robinhoodWei:$evm},
  token: {
    mint:.token.mint,
    deployerAta:.token.deployerAta,
    fixedSupplyRaw:.token.fixedSupplyRaw,
    mintAuthority:.token.mintAuthority,
    freezeAuthority:.token.freezeAuthority
  },
  solanaAdapter,
  evmOft,
  messages: [.messages[] | {direction,amountUi,guid,status,sourceTransaction,destinationTransaction}],
  invariants,
  externalBlockers
}' "$CHECKPOINT_FILE"

if [[ -n "$(json_get '.solanaAdapter.escrow // empty')" && -n "$(json_get '.evmOft.address // empty')" ]]; then
    pnpm ts-node --transpile-only scripts/snapshot-balances.ts
fi
