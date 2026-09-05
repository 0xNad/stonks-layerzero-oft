#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/mainnet-common.sh
source "$ROOT_DIR/scripts/lib/mainnet-common.sh"
cd "$ROOT_DIR"

load_mainnet_env
assert_mainnets

safe="$(json_get '.administration.robinhoodSafe.address')"
vault="$(json_get '.administration.solanaSquads.vault')"
program_id="$(json_get '.solanaAdapter.programId')"

DEPLOYMENT_ENV=mainnet ./scripts/verify-evm-source.sh
DEPLOYMENT_ENV=mainnet CHECKPOINT_FILE="$CHECKPOINT_FILE" pnpm ts-node --transpile-only scripts/inspect-evm-oft.ts

ADMIN_HANDOFF=1 EVM_ADMIN_SAFE="$safe" SOLANA_ADMIN_VAULT="$vault" DEPLOYMENT_ENV=mainnet \
    pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts --assert
ADMIN_HANDOFF=1 EVM_ADMIN_SAFE="$safe" SOLANA_ADMIN_VAULT="$vault" DEPLOYMENT_ENV=mainnet \
    pnpm hardhat lz:ownable:transfer-ownership --oapp-config layerzero.config.ts --assert

program_authority="$(solana program show "$program_id" --url "$SOLANA_RPC_URL" \
    --keypair "$SOLANA_KEYPAIR_PATH" --output json | jq -er '.authority')"
[[ "$program_authority" == "$vault" ]] || die "Solana program authority is $program_authority, expected $vault"

tmp="$(mktemp "$CHECKPOINT_FILE.tmp.XXXXXX")"
jq --arg safe "$safe" --arg vault "$vault" '
  if .solanaAdapter.sourceVerification.localHashMatch != true then error("Solana binary hash proof missing")
  elif .evmOft.sourceVerification != "PASS" or .evmOft.sourceVerificationMatch != "exact_match" then error("EVM exact source verification missing")
  elif .layerZero.configurationStatus != "PASS" or .layerZero.assertionStatus != "PASS" then error("LayerZero wiring proof missing")
  elif .solanaAdapter.programUpgradeAuthority != $vault then error("Solana upgrade authority handoff missing")
  elif .solanaAdapter.admin != $vault then error("Solana OFT admin handoff missing")
  elif .solanaAdapter.delegate != $vault then error("Solana LayerZero delegate handoff missing")
  elif .evmOft.owner != $safe then error("EVM ownership handoff missing")
  elif .evmOft.delegate != $safe then error("EVM LayerZero delegate handoff missing")
  else .adminHandoff={
         status:"PASS",
         verifiedAt:(now|todateiso8601),
         checks:{
           solanaProgramUpgradeAuthority:true,
           solanaOftAdmin:true,
           solanaLayerZeroDelegate:true,
           evmOwner:true,
           evmLayerZeroDelegate:true
         }
       } |
       if .canary.status == "PASS" and
          ([.canary.messages[] | select(.direction=="SOLANA_TO_EVM" and .status=="DELIVERED")] | length) >= 1 and
          ([.canary.messages[] | select(.direction=="EVM_TO_SOLANA" and .status=="DELIVERED")] | length) >= 1
       then .status="LIVE — DEPLOYED, WIRED, VERIFIED, ADMIN-HANDOFF AND ROUND-TRIP CANARY COMPLETE" |
            .externalBlockers=((.externalBlockers // []) | map(select(test("round-trip canary"; "i") | not)))
       else .status="LIVE — DEPLOYED, WIRED, VERIFIED, ADMIN-HANDOFF COMPLETE; CANARY PENDING STONKS"
       end |
       .updatedAt=(now|todateiso8601)
  end' "$CHECKPOINT_FILE" >"$tmp"
mv "$tmp" "$CHECKPOINT_FILE"

pnpm ts-node --transpile-only scripts/render-mainnet-result.ts
note "PASS: mainnet bridge infrastructure is deployed, wired, verified, and held by the temporary 1-of-1 admin containers"
if [[ "$(json_get '.canary.status')" == "PASS" ]]; then
    note "PASS: capped STONKS round-trip canary and supply invariants are complete"
else
    note "PENDING: capped round-trip canary requires STONKS in an operator-controlled Solana token account"
fi
