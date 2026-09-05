#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKPOINT_FILE="${CHECKPOINT_FILE:-$ROOT_DIR/deployments/mainnet.json}"
CONFIG_EVIDENCE_FILE="${CONFIG_EVIDENCE_FILE:-$ROOT_DIR/deployments/mainnet-configuration.json}"
SOLANA_KEYPAIR_PATH="${SOLANA_KEYPAIR_PATH:-.mainnet-secrets/solana-deployer.json}"
EVM_SECRET_FILE="${EVM_SECRET_FILE:-.mainnet-secrets/evm-deployer.env}"
SOLANA_RPC_URL="${RPC_URL_SOLANA_MAINNET:-https://api.mainnet-beta.solana.com}"
ROBINHOOD_RPC_URL="${RPC_URL_ROBINHOOD_MAINNET:-https://rpc.mainnet.chain.robinhood.com}"
SOLANA_EID=30168
ROBINHOOD_EID=30416
SOLANA_MAINNET_GENESIS_HASH="5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d"
ROBINHOOD_CHAIN_ID_HEX="0x1237"
TOKEN_PROGRAM_ID="TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
STONKS_MINT="stonksUpymwbn1rBBpZmd1u92ydJ2asGw1y7capGMzW"

SOLANA_CLI_DIR="${SOLANA_CLI_DIR:-${HOME}/.local/share/solana/install/active_release/bin}"
if ! command -v solana >/dev/null 2>&1 && [[ -x "$SOLANA_CLI_DIR/solana" ]]; then
    solana() { "$SOLANA_CLI_DIR/solana" "$@"; }
    solana-keygen() { "$SOLANA_CLI_DIR/solana-keygen" "$@"; }
fi

if command -v pnpm >/dev/null 2>&1; then
    HOST_PNPM_BIN="$(command -v pnpm)"
    pnpm() { "$HOST_PNPM_BIN" dlx pnpm@8.15.6 "$@"; }
fi

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_file() { [[ -f "$1" ]] || die "Required file not found: $1"; }
json_get() { jq -r "$1" "$CHECKPOINT_FILE"; }

checkpoint_arg() {
    local filter="$1"
    shift
    local tmp
    tmp="$(mktemp "$CHECKPOINT_FILE.tmp.XXXXXX")"
    jq "$@" "$filter | .updatedAt = (now | todateiso8601)" "$CHECKPOINT_FILE" >"$tmp"
    mv "$tmp" "$CHECKPOINT_FILE"
}

load_mainnet_env() {
    require_file "$SOLANA_KEYPAIR_PATH"
    require_file "$EVM_SECRET_FILE"
    [[ "$(stat -f '%Lp' "$SOLANA_KEYPAIR_PATH")" == "600" ]] || die "$SOLANA_KEYPAIR_PATH must have mode 600"
    [[ "$(stat -f '%Lp' "$EVM_SECRET_FILE")" == "600" ]] || die "$EVM_SECRET_FILE must have mode 600"
    set -a
    # shellcheck disable=SC1090
    source "$EVM_SECRET_FILE"
    set +a
    export DEPLOYMENT_ENV=mainnet
    export SOLANA_KEYPAIR_PATH
    export RPC_URL_SOLANA_MAINNET="$SOLANA_RPC_URL"
    export RPC_URL_SOLANA="$SOLANA_RPC_URL"
    export RPC_URL_ROBINHOOD_MAINNET="$ROBINHOOD_RPC_URL"
    export CHECKPOINT_FILE CONFIG_EVIDENCE_FILE
    [[ -n "${PRIVATE_KEY:-}" ]] || die "PRIVATE_KEY is missing from $EVM_SECRET_FILE"
}

solana_rpc() {
    local method="$1" params="${2:-[]}"
    curl --fail-with-body --silent --show-error "$SOLANA_RPC_URL" -H 'Content-Type: application/json' \
        --data "$(jq -nc --arg method "$method" --argjson params "$params" '{jsonrpc:"2.0",id:1,method:$method,params:$params}')"
}

evm_rpc() {
    local method="$1" params="${2:-[]}"
    curl --fail-with-body --silent --show-error "$ROBINHOOD_RPC_URL" -H 'Content-Type: application/json' \
        --data "$(jq -nc --arg method "$method" --argjson params "$params" '{jsonrpc:"2.0",id:1,method:$method,params:$params}')"
}

assert_mainnets() {
    local genesis chain_id
    genesis="$(solana_rpc getGenesisHash | jq -er '.result')"
    [[ "$genesis" == "$SOLANA_MAINNET_GENESIS_HASH" ]] || die "Refusing Solana write: unexpected genesis $genesis"
    chain_id="$(evm_rpc eth_chainId | jq -er '.result' | tr '[:upper:]' '[:lower:]')"
    [[ "$chain_id" == "$ROBINHOOD_CHAIN_ID_HEX" ]] || die "Refusing EVM write: chain ID is $chain_id, not Robinhood 4663"
}

solana_balance_lamports() {
    solana_rpc getBalance "$(jq -nc --arg address "$1" '[$address,{commitment:"confirmed"}]')" | jq -er '.result.value'
}

evm_balance_wei() {
    local hex
    hex="$(evm_rpc eth_getBalance "$(jq -nc --arg address "$1" '[$address,"latest"]')" | jq -er '.result')"
    node -e 'console.log(BigInt(process.argv[1]).toString())' "$hex"
}

decimal_to_units() {
    local amount="$1" decimals="$2"
    node -e '
const [whole, fraction = ""] = process.argv[1].split(".")
const decimals = Number(process.argv[2])
if (fraction.length > decimals) throw new Error("too many decimal places")
console.log((BigInt(whole) * 10n ** BigInt(decimals) + BigInt((fraction + "0".repeat(decimals)).slice(0, decimals) || "0")).toString())
' "$amount" "$decimals"
}

ensure_solana_mainnet_deployment_file() {
    local output="$ROOT_DIR/deployments/solana-mainnet/OFT.json"
    [[ -f "$output" ]] && return 0
    local program mint store escrow
    program="$(json_get '.solanaAdapter.programId // empty')"
    mint="$(json_get '.token.mint // empty')"
    store="$(json_get '.solanaAdapter.oftStore // empty')"
    escrow="$(json_get '.solanaAdapter.escrow // empty')"
    [[ -n "$program" && -n "$mint" && -n "$store" && -n "$escrow" ]] || die "Mainnet adapter checkpoint is incomplete"
    mkdir -p "$(dirname "$output")"
    jq -n --arg program "$program" --arg mint "$mint" --arg escrow "$escrow" --arg store "$store" \
        '{programId:$program,mint:$mint,mintAuthority:"",escrow:$escrow,oftStore:$store}' >"$output"
}

cd "$ROOT_DIR"
