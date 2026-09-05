#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

for command in node pnpm jq; do require_cmd "$command"; done
load_testnet_env
assert_public_testnets

solana_address="$(json_get '.wallets.solana')"
lamports="$(solana_balance_lamports "$solana_address")"
((lamports >= 20000000)) || die "At least 0.02 Devnet SOL is required to create and freeze tSTONKS; found $lamports lamports"

pnpm ts-node --transpile-only scripts/create-solana-token.ts
