#!/usr/bin/env bash

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
cd "$ROOT_DIR"

if [[ "${RESET:-0}" == "1" ]]; then
    RESET=1 RESET_KEYS="${RESET_KEYS:-0}" ./scripts/reset-testnet.sh
fi

if [[ "${ROUNDTRIP_ONLY:-0}" != "1" ]]; then
    ./scripts/bootstrap.sh
    MIN_SOLANA_LAMPORTS="${MIN_SOLANA_LAMPORTS:-4200000000}" ./scripts/fund-wallets.sh
    ./scripts/create-admins.sh
    ./scripts/create-solana-token.sh
    if [[ "${SKIP_VERIFIABLE_BUILD:-0}" != "1" ]]; then
        ./scripts/build-solana-verifiable.sh
    fi
    ./scripts/deploy-solana-adapter.sh
    ./scripts/verify-solana-source.sh
    ./scripts/deploy-evm-oft.sh
    ./scripts/verify-evm-source.sh
    ./scripts/wire.sh
    ./scripts/send-solana-to-evm.sh "${S2E_AMOUNT:-1000}"
    ./scripts/send-evm-to-solana.sh "${E2S_AMOUNT:-400}"
    ./scripts/send-solana-to-evm.sh "${REUSE_AMOUNT:-10}"
else
    ./scripts/status.sh
    ./scripts/send-solana-to-evm.sh "${S2E_AMOUNT:-10}"
    ./scripts/send-evm-to-solana.sh "${E2S_AMOUNT:-10}"
fi

./scripts/handoff-admins.sh
./scripts/finalize-testnet.sh
