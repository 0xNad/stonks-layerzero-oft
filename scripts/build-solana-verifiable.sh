#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
for command in docker id mktemp rsync shasum solana-verify; do
    command -v "$command" >/dev/null 2>&1 || {
        printf 'ERROR: required command not found: %s\n' "$command" >&2
        exit 1
    }
done
docker info >/dev/null 2>&1 || {
    printf 'ERROR: Docker daemon is not available\n' >&2
    exit 1
}

# Colima does not mount external /Volumes paths into its VM by default. Stage
# source under /Users, which is shared with the VM, without copying secrets,
# deployments, generated artifacts, or repository metadata.
stage_parent="${STONKS_VERIFY_TEMP_ROOT:-/Users/$(id -un)}"
[[ -d "$stage_parent" ]] || {
    printf 'ERROR: verification staging parent does not exist: %s\n' "$stage_parent" >&2
    exit 1
}
stage_dir="$(mktemp -d "$stage_parent/stonks-svb.XXXXXX")"
cleanup() {
    [[ "$stage_dir" == "$stage_parent"/stonks-svb.* ]] && rm -rf "$stage_dir"
}
trap cleanup EXIT

rsync -a \
    --exclude='.git/' \
    --exclude='.testnet-secrets/' \
    --exclude='.mainnet-secrets/' \
    --exclude='node_modules/' \
    --exclude='target/' \
    --exclude='artifacts/' \
    --exclude='cache/' \
    --exclude='deployments/' \
    "$ROOT_DIR/" "$stage_dir/"

solana-verify build --library-name oft "$stage_dir"
binary="$stage_dir/target/deploy/oft.so"
[[ -f "$binary" ]] || {
    printf 'ERROR: verifier did not produce %s\n' "$binary" >&2
    exit 1
}

mkdir -p "$ROOT_DIR/target/verifiable"
install -m 755 "$binary" "$ROOT_DIR/target/verifiable/oft.so"
printf 'PASS: deterministic binary %s (%s bytes, sha256 %s)\n' \
    "$ROOT_DIR/target/verifiable/oft.so" \
    "$(stat -f '%z' "$ROOT_DIR/target/verifiable/oft.so")" \
    "$(shasum -a 256 "$ROOT_DIR/target/verifiable/oft.so" | awk '{print $1}')"
