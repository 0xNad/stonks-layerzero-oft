#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "${DEPLOYMENT_ENV:-testnet}" == "mainnet" ]]; then
    # shellcheck source=scripts/lib/mainnet-common.sh
    source "$SCRIPT_DIR/lib/mainnet-common.sh"
    load_mainnet_env
    assert_mainnets
else
    # shellcheck source=scripts/lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
    load_testnet_env
    assert_public_testnets
fi
for command in jq node pnpm; do require_cmd "$command"; done
if [[ -z "$(json_get '.administration.robinhoodSafe.address // empty')" ]]; then
    evm_address="$(json_get '.wallets.evm')"
    evm_wei="$(evm_balance_wei "$evm_address")"
    [[ "$(node -e 'console.log(BigInt(process.argv[1]) >= 1000000000000000n ? "yes" : "no")' "$evm_wei")" == "yes" ]] || \
        die "At least 0.001 native ETH is required to create the Robinhood Safe; found $evm_wei wei"
fi
pnpm ts-node --transpile-only scripts/create-admins.ts
