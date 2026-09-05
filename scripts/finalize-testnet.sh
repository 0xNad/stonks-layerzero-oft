#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
cd "$ROOT_DIR"

load_testnet_env
assert_public_testnets

pnpm ts-node --transpile-only scripts/verify-invariants.ts

tmp="$(mktemp "$CHECKPOINT_FILE.tmp.XXXXXX")"
jq '
  if .invariants.status != "PASS" then error("invariants did not pass")
  elif ([.messages[] | select(.status=="DELIVERED" and .guid!=null and .destinationTransaction!=null)] | length) < 2 then error("fewer than two delivered messages")
  elif ([.messages[] | select(.direction=="SOLANA_TO_EVM" and .status=="DELIVERED")] | length) < 1 then error("missing Solana to EVM delivery")
  elif ([.messages[] | select(.direction=="EVM_TO_SOLANA" and .status=="DELIVERED")] | length) < 1 then error("missing EVM to Solana delivery")
  elif .solanaAdapter.programUpgradeAuthority != .administration.solanaSquads.vault then error("Solana upgrade authority was not handed off")
  elif .solanaAdapter.admin != .administration.solanaSquads.vault then error("Solana OFT admin was not handed off")
  elif .solanaAdapter.delegate != .administration.solanaSquads.vault then error("Solana LayerZero delegate was not handed off")
  elif .evmOft.owner != .administration.robinhoodSafe.address then error("EVM ownership was not handed off")
  elif .evmOft.delegate != .administration.robinhoodSafe.address then error("EVM LayerZero delegate was not handed off")
  else .status="PASS — COMPLETE OFT ADAPTER TESTNET PROOF" | .externalBlockers=[] | .updatedAt=(now|todateiso8601)
  end' "$CHECKPOINT_FILE" >"$tmp"
mv "$tmp" "$CHECKPOINT_FILE"

pnpm ts-node --transpile-only scripts/render-run-result.ts
./scripts/status.sh
printf 'PASS — COMPLETE OFT ADAPTER TESTNET PROOF\n'
