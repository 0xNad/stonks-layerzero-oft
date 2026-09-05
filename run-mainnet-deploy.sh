#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/mainnet-common.sh
source "$ROOT_DIR/scripts/lib/mainnet-common.sh"
cd "$ROOT_DIR"

for command in git jq; do require_cmd "$command"; done
[[ -z "$(git status --porcelain)" ]] || die "Refusing mainnet deployment from a dirty worktree"
source_commit="$(git rev-parse HEAD)"
remote_commit="$(git ls-remote origin refs/heads/master | awk '{print $1}')"
[[ -n "$remote_commit" && "$source_commit" == "$remote_commit" ]] || \
    die "Refusing mainnet deployment: local HEAD is not the pushed origin/master commit"

./scripts/materialize-keychain-secrets.sh
if [[ "${SKIP_VERIFIABLE_BUILD:-0}" != "1" ]]; then
    ./scripts/build-solana-verifiable.sh
fi
checkpoint_arg '.sourceCommit=$commit' --arg commit "$source_commit"
DEPLOYMENT_ENV=mainnet pnpm ts-node --transpile-only scripts/check-layerzero-readiness.ts
DEPLOYMENT_ENV=mainnet ./scripts/create-admins.sh
./scripts/deploy-solana-mainnet.sh
DEPLOYMENT_ENV=mainnet ./scripts/verify-solana-source.sh
./scripts/deploy-evm-mainnet.sh
DEPLOYMENT_ENV=mainnet ./scripts/verify-evm-source.sh
./scripts/wire-mainnet.sh
DEPLOYMENT_ENV=mainnet ./scripts/handoff-admins.sh

tmp="$(mktemp "$CHECKPOINT_FILE.tmp.XXXXXX")"
jq '
  if .solanaAdapter.sourceVerification.localHashMatch != true then error("Solana binary hash proof missing")
  elif .evmOft.sourceVerification != "PASS" then error("EVM source verification missing")
  elif .layerZero.configurationStatus != "PASS" or .layerZero.assertionStatus != "PASS" then error("LayerZero wiring proof missing")
  elif .solanaAdapter.programUpgradeAuthority != .administration.solanaSquads.vault then error("Solana upgrade authority handoff missing")
  elif .solanaAdapter.admin != .administration.solanaSquads.vault then error("Solana OFT admin handoff missing")
  elif .solanaAdapter.delegate != .administration.solanaSquads.vault then error("Solana LayerZero delegate handoff missing")
  elif .evmOft.owner != .administration.robinhoodSafe.address then error("EVM ownership handoff missing")
  elif .evmOft.delegate != .administration.robinhoodSafe.address then error("EVM LayerZero delegate handoff missing")
  else .status="LIVE — DEPLOYED, WIRED, VERIFIED, ADMIN-HANDOFF COMPLETE; CANARY PENDING STONKS" |
       .updatedAt=(now|todateiso8601)
  end' "$CHECKPOINT_FILE" >"$tmp"
mv "$tmp" "$CHECKPOINT_FILE"

note "PASS: mainnet bridge infrastructure is deployed, wired, verified, and held by the temporary 1-of-1 admin containers"
note "PENDING: capped round-trip canary requires STONKS in an operator-controlled Solana token account"
