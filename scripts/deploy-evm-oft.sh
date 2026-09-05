#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

for command in jq node pnpm; do require_cmd "$command"; done
load_testnet_env
assert_public_testnets

evm_address="$(json_get '.wallets.evm')"
wei="$(evm_balance_wei "$evm_address")"
[[ "$(node -e 'console.log(BigInt(process.argv[1]) >= 1000000000000000n ? "yes" : "no")' "$wei")" == "yes" ]] || \
    die "At least 0.001 Robinhood testnet ETH is required; found $wei wei"

deployment_file="$ROOT_DIR/deployments/robinhood-testnet/StonksOFT.json"
checkpoint_address="$(json_get '.evmOft.address // empty')"
if [[ -n "$checkpoint_address" && ! -f "$deployment_file" ]]; then
    die "Checkpoint protects EVM OFT $checkpoint_address, but its deployment artifact is missing"
fi

pnpm compile:hardhat
pnpm test:hardhat
if [[ ! -f "$deployment_file" ]]; then
    pnpm hardhat lz:deploy --networks robinhood-testnet --tags StonksOFT --ci
fi
require_file "$deployment_file"

artifact_address="$(jq -r '.address' "$deployment_file")"
checkpoint_address_lower="$(printf '%s' "$checkpoint_address" | tr '[:upper:]' '[:lower:]')"
artifact_address_lower="$(printf '%s' "$artifact_address" | tr '[:upper:]' '[:lower:]')"
if [[ -n "$checkpoint_address" && "$checkpoint_address_lower" != "$artifact_address_lower" ]]; then
    die "Refusing duplicate OFT: artifact $artifact_address differs from checkpoint $checkpoint_address"
fi

pnpm ts-node --transpile-only scripts/inspect-evm-oft.ts
