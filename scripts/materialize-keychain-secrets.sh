#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTNET_DIR="$ROOT_DIR/.testnet-secrets"
MAINNET_DIR="$ROOT_DIR/.mainnet-secrets"
cd "$ROOT_DIR"

command -v security >/dev/null 2>&1 || {
    printf 'ERROR: macOS security command is required\n' >&2
    exit 1
}
command -v solana-keygen >/dev/null 2>&1 || {
    SOLANA_KEYGEN="$HOME/.local/share/solana/install/active_release/bin/solana-keygen"
    [[ -x "$SOLANA_KEYGEN" ]] || {
        printf 'ERROR: solana-keygen is required\n' >&2
        exit 1
    }
}
SOLANA_KEYGEN="${SOLANA_KEYGEN:-$(command -v solana-keygen)}"

umask 077
mkdir -p "$TESTNET_DIR" "$MAINNET_DIR"
chmod 700 "$TESTNET_DIR" "$MAINNET_DIR"

write_keychain_value() {
    local service="$1" account="$2" output="$3" tmp
    tmp="$(mktemp "$output.tmp.XXXXXX")"
    security find-generic-password -s "$service" -a "$account" -w >"$tmp"
    printf '\n' >>"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$output"
}

write_evm_env() {
    local service="$1" account="$2" address="$3" output="$4" secret tmp
    secret="$(security find-generic-password -s "$service" -a "$account" -w)"
    [[ "$secret" =~ ^0x[0-9a-fA-F]{64}$ ]] || {
        printf 'ERROR: invalid EVM key in Keychain service %s account %s\n' "$service" "$account" >&2
        exit 1
    }
    tmp="$(mktemp "$output.tmp.XXXXXX")"
    printf 'PRIVATE_KEY=%s\nEVM_ADDRESS=%s\n' "$secret" "$address" >"$tmp"
    unset secret
    chmod 600 "$tmp"
    mv "$tmp" "$output"
}

write_keychain_value stonks-layerzero-testnet solana-deployer "$TESTNET_DIR/solana-deployer.json"
write_evm_env stonks-layerzero-testnet evm-deployer \
    0x131625bbC0c0377812421Ca606dB8725f17ad931 "$TESTNET_DIR/evm-deployer.env"

write_keychain_value stonks-layerzero-mainnet solana-bootstrap-deployer "$MAINNET_DIR/solana-deployer.json"
write_evm_env stonks-layerzero-mainnet evm-bootstrap-deployer \
    0x53B4fA15cCc227c85a07531Dd4a830a8345a5e7c "$MAINNET_DIR/evm-deployer.env"
write_keychain_value stonks-layerzero-mainnet solana-oft-program-keypair \
    "$MAINNET_DIR/oft-program-keypair.json"

# The program account keypair establishes the public program ID only; it is not
# the upgrade authority. Reuse the same verified program ID on Devnet.
cp "$MAINNET_DIR/oft-program-keypair.json" "$TESTNET_DIR/oft-program-keypair.json"
chmod 600 "$TESTNET_DIR/oft-program-keypair.json"

for scope in testnet mainnet; do
    directory="$ROOT_DIR/.${scope}-secrets"
    create_key="$directory/squads-create-key.json"
    if [[ ! -f "$create_key" ]]; then
        "$SOLANA_KEYGEN" new --no-bip39-passphrase --silent --outfile "$create_key" >/dev/null
    fi
    chmod 600 "$create_key"
done

[[ "$($SOLANA_KEYGEN pubkey .testnet-secrets/solana-deployer.json)" == \
    "BTvyuzjPozDCLjvhjTsxgBfqeQoKgexEMRyyXvxvvUyN" ]] || {
    printf 'ERROR: testnet Solana Keychain entry does not match its public address\n' >&2
    exit 1
}
[[ "$($SOLANA_KEYGEN pubkey .mainnet-secrets/solana-deployer.json)" == \
    "CvukDFaypgVZzpcksdnJTWJbVgybYeeUZzsBhANXj1ix" ]] || {
    printf 'ERROR: mainnet Solana Keychain entry does not match its public address\n' >&2
    exit 1
}
[[ "$($SOLANA_KEYGEN pubkey .mainnet-secrets/oft-program-keypair.json)" == \
    "6Zxe2WqArgpooREBXPFmyA3fGywgBRccFtYYePZ96tTF" ]] || {
    printf 'ERROR: OFT program Keychain entry does not match the compiled program ID\n' >&2
    exit 1
}

printf 'PASS: Keychain secrets materialized into ignored mode-600 files\n'
