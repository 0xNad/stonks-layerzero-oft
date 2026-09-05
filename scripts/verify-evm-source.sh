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

if [[ "$environment" == "mainnet" ]]; then
    sourcify_url="https://sourcify.dev/server/v2/contract/4663/$address"
    sourcify_response="$(curl --silent --show-error "$sourcify_url")"
    if [[ "$(jq -r '.match // empty' <<<"$sourcify_response")" != "exact_match" ]]; then
        input_hash="$(jq -er '.solcInputHash' "$deployment")"
        solc_input="$ROOT_DIR/deployments/$network/solcInputs/$input_hash.json"
        compiler_version="$(jq -er '.metadata | fromjson | .compiler.version' "$deployment")"
        creation_transaction="$(jq -er '.transactionHash' "$deployment")"
        require_file "$solc_input"

        submission="$(jq -nc --slurpfile input "$solc_input" \
            --arg compiler "$compiler_version" --arg transaction "$creation_transaction" \
            '{stdJsonInput:$input[0], compilerVersion:$compiler,
              contractIdentifier:"contracts/MyOFT.sol:StonksOFT", creationTransactionHash:$transaction}')"
        submission_response="$(curl --fail-with-body --silent --show-error \
            -X POST "https://sourcify.dev/server/v2/verify/4663/$address" \
            -H 'Content-Type: application/json' --data-binary "$submission")"
        verification_id="$(jq -er '.verificationId' <<<"$submission_response")"

        job_response=''
        for _ in {1..60}; do
            job_response="$(curl --fail-with-body --silent --show-error \
                "https://sourcify.dev/server/v2/verify/$verification_id")"
            [[ "$(jq -r '.isJobCompleted // false' <<<"$job_response")" == "true" ]] && break
            sleep 3
        done
        [[ "$(jq -r '.isJobCompleted // false' <<<"$job_response")" == "true" ]] || \
            die "Sourcify verification job $verification_id did not complete"
        [[ "$(jq -r '.contract.match // empty' <<<"$job_response")" == "exact_match" ]] || \
            die "Sourcify verification job $verification_id did not produce an exact match"
        sourcify_response="$(curl --fail-with-body --silent --show-error "$sourcify_url")"
    fi
    [[ "$(jq -r '.match // empty' <<<"$sourcify_response")" == "exact_match" ]] || \
        die "Sourcify did not report an exact match for $address"
    [[ "$(jq -r '.creationMatch // empty' <<<"$sourcify_response")" == "exact_match" ]] || \
        die "Sourcify did not report exact creation bytecode for $address"
    [[ "$(jq -r '.runtimeMatch // empty' <<<"$sourcify_response")" == "exact_match" ]] || \
        die "Sourcify did not report exact runtime bytecode for $address"

    match_id="$(jq -er '.matchId' <<<"$sourcify_response")"
    verified_at="$(jq -er '.verifiedAt' <<<"$sourcify_response")"
    checkpoint_arg \
        '.evmOft.sourceVerification="PASS" |
         .evmOft.sourceVerificationProvider="Sourcify" |
         .evmOft.sourceVerificationMatch="exact_match" |
         .evmOft.sourceVerificationMatchId=$matchId |
         .evmOft.sourceVerificationUrl=$url |
         .evmOft.sourceVerificationCheckedAt=(now|todateiso8601) |
         .evmOft.sourceVerifiedAt=$verifiedAt' \
        --arg matchId "$match_id" --arg url "$sourcify_url" --arg verifiedAt "$verified_at"
    note "PASS: Sourcify exact creation/runtime source match for $address"
    exit 0
fi

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
