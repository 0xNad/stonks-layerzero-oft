#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKPOINT_FILE="${CHECKPOINT_FILE:-$ROOT_DIR/deployments/testnet.json}"
CONFIG_EVIDENCE_FILE="${CONFIG_EVIDENCE_FILE:-$ROOT_DIR/deployments/testnet-configuration.json}"
SOLANA_KEYPAIR_PATH="${SOLANA_KEYPAIR_PATH:-.testnet-secrets/solana-deployer.json}"
EVM_SECRET_FILE="${EVM_SECRET_FILE:-.testnet-secrets/evm-deployer.env}"
SOLANA_RPC_URL="${RPC_URL_SOLANA_TESTNET:-${RPC_URL_SOLANA:-https://api.devnet.solana.com}}"
ROBINHOOD_RPC_URL="${RPC_URL_ROBINHOOD_TESTNET:-https://rpc.testnet.chain.robinhood.com}"
SOLANA_EID=40168
ROBINHOOD_EID=40451
SOLANA_DEVNET_GENESIS_HASH="EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG"
ROBINHOOD_CHAIN_ID_HEX="0xb626"
TOKEN_PROGRAM_ID="TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"

# The Agave installer keeps its selected release behind this stable symlink but
# does not always update non-interactive shells. Use it without mutating PATH.
SOLANA_CLI_DIR="${SOLANA_CLI_DIR:-${HOME}/.local/share/solana/install/active_release/bin}"
if ! command -v solana >/dev/null 2>&1 && [[ -x "$SOLANA_CLI_DIR/solana" ]]; then
    solana() { "$SOLANA_CLI_DIR/solana" "$@"; }
    solana-keygen() { "$SOLANA_CLI_DIR/solana-keygen" "$@"; }
    spl-token() { "$SOLANA_CLI_DIR/spl-token" "$@"; }
fi

# The host currently carries a newer pnpm. Every operator wrapper deliberately
# dispatches the exact upstream version without mutating the user's global tool.
if command -v pnpm >/dev/null 2>&1; then
    HOST_PNPM_BIN="$(command -v pnpm)"
    pnpm() {
        "$HOST_PNPM_BIN" dlx pnpm@8.15.6 "$@"
    }
fi

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

note() {
    printf '%s\n' "$*"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_file() {
    [[ -f "$1" ]] || die "Required file not found: $1"
}

json_get() {
    local filter="$1"
    jq -r "$filter" "$CHECKPOINT_FILE"
}

checkpoint_apply() {
    local filter="$1"
    local tmp
    tmp="$(mktemp "$CHECKPOINT_FILE.tmp.XXXXXX")"
    jq "$filter | .updatedAt = (now | todateiso8601)" "$CHECKPOINT_FILE" >"$tmp"
    mv "$tmp" "$CHECKPOINT_FILE"
}

checkpoint_arg() {
    local filter="$1"
    shift
    local tmp
    tmp="$(mktemp "$CHECKPOINT_FILE.tmp.XXXXXX")"
    jq "$@" "$filter | .updatedAt = (now | todateiso8601)" "$CHECKPOINT_FILE" >"$tmp"
    mv "$tmp" "$CHECKPOINT_FILE"
}

load_testnet_env() {
    require_file "$SOLANA_KEYPAIR_PATH"
    require_file "$EVM_SECRET_FILE"

    local key_mode secret_mode
    key_mode="$(stat -f '%Lp' "$SOLANA_KEYPAIR_PATH")"
    secret_mode="$(stat -f '%Lp' "$EVM_SECRET_FILE")"
    [[ "$key_mode" == "600" ]] || die "$SOLANA_KEYPAIR_PATH must have mode 600 (found $key_mode)"
    [[ "$secret_mode" == "600" ]] || die "$EVM_SECRET_FILE must have mode 600 (found $secret_mode)"

    set -a
    # shellcheck disable=SC1090
    source "$EVM_SECRET_FILE"
    set +a

    export SOLANA_KEYPAIR_PATH
    export RPC_URL_SOLANA_TESTNET="$SOLANA_RPC_URL"
    export RPC_URL_SOLANA="$SOLANA_RPC_URL"
    export RPC_URL_ROBINHOOD_TESTNET="$ROBINHOOD_RPC_URL"
    [[ -n "${PRIVATE_KEY:-}" ]] || die "PRIVATE_KEY is missing from $EVM_SECRET_FILE"
}

solana_rpc() {
    local method="$1"
    local params="${2:-[]}"
    curl --fail-with-body --silent --show-error "$SOLANA_RPC_URL" \
        -H 'Content-Type: application/json' \
        --data "$(jq -nc --arg method "$method" --argjson params "$params" \
            '{jsonrpc:"2.0",id:1,method:$method,params:$params}')"
}

evm_rpc() {
    local method="$1"
    local params="${2:-[]}"
    curl --fail-with-body --silent --show-error "$ROBINHOOD_RPC_URL" \
        -H 'Content-Type: application/json' \
        --data "$(jq -nc --arg method "$method" --argjson params "$params" \
            '{jsonrpc:"2.0",id:1,method:$method,params:$params}')"
}

assert_public_testnets() {
    local genesis chain_id
    genesis="$(solana_rpc getGenesisHash | jq -er '.result')"
    [[ "$genesis" == "$SOLANA_DEVNET_GENESIS_HASH" ]] || \
        die "Refusing Solana write: RPC genesis is $genesis, not Devnet"

    chain_id="$(evm_rpc eth_chainId | jq -er '.result' | tr '[:upper:]' '[:lower:]')"
    [[ "$chain_id" == "$ROBINHOOD_CHAIN_ID_HEX" ]] || \
        die "Refusing EVM write: RPC chain ID is $chain_id, not Robinhood Testnet 46630"
}

ensure_solana_deployment_file() {
    local output="$ROOT_DIR/deployments/solana-testnet/OFT.json"
    [[ -f "$output" ]] && return 0

    local program mint store escrow
    program="$(json_get '.solanaAdapter.programId // empty')"
    mint="$(json_get '.token.mint // empty')"
    store="$(json_get '.solanaAdapter.oftStore // empty')"
    escrow="$(json_get '.solanaAdapter.escrow // empty')"
    [[ -n "$program" && -n "$mint" && -n "$store" && -n "$escrow" ]] || \
        die "Cannot reconstruct Solana deployment file: adapter checkpoint is incomplete"

    mkdir -p "$(dirname "$output")"
    local tmp
    tmp="$(mktemp "$output.tmp.XXXXXX")"
    jq -n \
        --arg program "$program" \
        --arg mint "$mint" \
        --arg escrow "$escrow" \
        --arg store "$store" \
        '{programId:$program,mint:$mint,mintAuthority:"",escrow:$escrow,oftStore:$store}' >"$tmp"
    mv "$tmp" "$output"
}

solana_balance_lamports() {
    local address="$1"
    solana_rpc getBalance "$(jq -nc --arg address "$address" '[$address,{commitment:"confirmed"}]')" | \
        jq -er '.result.value'
}

evm_balance_wei() {
    local address="$1"
    local hex
    hex="$(evm_rpc eth_getBalance "$(jq -nc --arg address "$address" '[$address,"latest"]')" | jq -er '.result')"
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

retry() {
    local attempts="$1"
    shift
    local delay=2 n=1
    until "$@"; do
        if ((n >= attempts)); then
            return 1
        fi
        note "Attempt $n failed; retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))
        n=$((n + 1))
    done
}

cd "$ROOT_DIR"
