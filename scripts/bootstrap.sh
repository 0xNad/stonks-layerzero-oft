#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

for command in git curl jq node pnpm rustc cargo solana solana-keygen anchor; do
    require_cmd "$command"
done
load_testnet_env
assert_public_testnets

node -e '
const [major, minor] = process.versions.node.split(".").map(Number)
if (major < 20 || (major === 20 && minor < 19)) {
  throw new Error(`Node >=20.19.5 is required; found ${process.versions.node}`)
}
'

[[ "$(rustc --version | awk '{print $2}')" == "1.84.1" ]] || \
    die "Rust 1.84.1 is required by rust-toolchain.toml"
[[ "$(solana --version | awk '{print $2}')" == "2.2.20" ]] || \
    die "Solana CLI 2.2.20 is required"
[[ "$(anchor --version | awk '{print $2}')" == "0.31.1" ]] || \
    die "Anchor CLI 0.31.1 is required"
[[ "$(pnpm --version)" == "8.15.6" ]] || die "Project pnpm dispatch did not resolve 8.15.6"

pnpm install --frozen-lockfile
pnpm compile:hardhat
pnpm test:hardhat

git check-ignore -q .testnet-secrets/solana-deployer.json || \
    die ".testnet-secrets is not ignored by git"
git check-ignore -q .testnet-secrets/evm-deployer.env || \
    die ".testnet-secrets is not ignored by git"

note "PASS: dependencies, pinned versions, secrets, testnet RPCs, Solidity compile, and unit tests validated"
