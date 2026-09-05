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
./scripts/finalize-mainnet.sh
