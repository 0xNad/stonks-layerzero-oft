#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
environment="${DEPLOYMENT_ENV:-testnet}"
if [[ "$environment" == "mainnet" ]]; then
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

for command in jq solana-verify; do require_cmd "$command"; done

program_id="$(json_get '.solanaAdapter.programId // empty')"
[[ -n "$program_id" ]] || die "Solana OFT program ID is missing"

binary="${OFT_PROGRAM_BINARY:-$ROOT_DIR/target/verifiable/oft.so}"
[[ -f "$binary" ]] || binary="$ROOT_DIR/target/deploy/oft.so"
require_file "$binary"

binary_hash="$(solana-verify get-executable-hash "$binary" | tr -d '[:space:]')"
onchain_hash="$(solana-verify get-program-hash -u "$SOLANA_RPC_URL" "$program_id" | tr -d '[:space:]')"
[[ "$binary_hash" =~ ^[0-9a-f]{64}$ ]] || die "Unexpected local executable hash: $binary_hash"
[[ "$onchain_hash" =~ ^[0-9a-f]{64}$ ]] || die "Unexpected on-chain executable hash: $onchain_hash"
[[ "$binary_hash" == "$onchain_hash" ]] || die "Local deterministic binary does not match deployed program"

checkpoint_arg \
    '.solanaAdapter.sourceVerification={status:"LOCAL_HASH_MATCH",localHashMatch:true,binaryHash:$binary,onchainHash:$onchain,checkedAt:(now|todateiso8601),publicRepositoryVerification:"PENDING_PUBLIC_REPOSITORY"}' \
    --arg binary "$binary_hash" --arg onchain "$onchain_hash"

note "PASS: local executable hash matches deployed Solana program ($binary_hash)"
note "NOTICE: public source badge remains pending while the GitHub repository is private"
