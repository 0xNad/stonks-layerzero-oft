#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
environment="${DEPLOYMENT_ENV:-testnet}"
if [[ "$environment" == "mainnet" ]]; then
    # shellcheck source=scripts/lib/mainnet-common.sh
    source "$SCRIPT_DIR/lib/mainnet-common.sh"
    load_mainnet_env
    assert_mainnets
    network="robinhood-mainnet"
    explorer_api="https://robinhoodchain.blockscout.com/api"
else
    # shellcheck source=scripts/lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
    load_testnet_env
    assert_public_testnets
    network="robinhood-testnet"
    explorer_api="https://explorer.testnet.chain.robinhood.com/api"
fi

for command in curl jq pnpm; do require_cmd "$command"; done
deployment="$ROOT_DIR/deployments/$network/StonksOFT.json"
require_file "$deployment"
address="$(jq -er '.address' "$deployment")"
name="$(json_get '.evmOft.name')"
symbol="$(json_get '.evmOft.symbol')"
endpoint="$(json_get '.evmOft.endpoint')"
owner="$(json_get '.wallets.evm')"

verification_output="$(mktemp "${TMPDIR:-/tmp}/stonks-evm-verify.XXXXXX")"
set +e
pnpm hardhat verify --network "$network" "$address" "$name" "$symbol" "$endpoint" "$owner" \
    >"$verification_output" 2>&1
verify_status=$?
set -e
cat "$verification_output"
if ((verify_status != 0)) && ! rg -qi 'already verified|already been verified' "$verification_output"; then
    die "Blockscout source verification submission failed"
fi

verified="false"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    response="$(curl --fail-with-body --silent --show-error --get "$explorer_api" \
        --data-urlencode module=contract --data-urlencode action=getsourcecode --data-urlencode address="$address")"
    abi="$(jq -r '.result[0].ABI // empty' <<<"$response")"
    contract_name="$(jq -r '.result[0].ContractName // empty' <<<"$response")"
    if [[ -n "$contract_name" && "$abi" != "Contract source code not verified" && "$abi" != "" ]]; then
        verified="true"
        break
    fi
    sleep 3
done
[[ "$verified" == "true" ]] || die "Blockscout did not report verified source for $address"
checkpoint_arg '.evmOft.sourceVerification="PASS" | .evmOft.sourceVerificationCheckedAt=(now|todateiso8601)'
note "PASS: Blockscout source verified for $address"
