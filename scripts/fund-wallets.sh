#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

for command in curl jq node; do require_cmd "$command"; done
load_testnet_env
assert_public_testnets

solana_address="$(json_get '.wallets.solana')"
evm_address="$(json_get '.wallets.evm')"
# A 4.2 SOL threshold covers the observed ~2.906 SOL program rent plus the
# Adapter, configuration, and transaction costs with a retry margin.
# After that deployment and Adapter initialization are checkpointed, retain a
# smaller operational floor so idempotent rehearsals do not mine rent twice.
if [[ -n "${MIN_SOLANA_LAMPORTS:-}" ]]; then
    min_solana_lamports="$MIN_SOLANA_LAMPORTS"
elif jq -e '
    (.solanaAdapter.programDeploymentTransactions | length) > 0 and
    (.solanaAdapter.oftStore // "") != "" and
    (.solanaAdapter.escrow // "") != ""
' "$CHECKPOINT_FILE" >/dev/null; then
    min_solana_lamports=100000000
else
    min_solana_lamports=4200000000
fi
min_evm_wei="${MIN_EVM_WEI:-3000000000000000}"

request_airdrop_once() {
    local amount="$1" response signature
    response="$(solana_rpc requestAirdrop "$(jq -nc --arg address "$solana_address" --argjson amount "$amount" \
        '[$address,$amount,{commitment:"confirmed"}]')" || true)"
    signature="$(jq -r '.result // empty' <<<"$response")"
    if [[ -n "$signature" ]]; then
        note "Solana airdrop submitted: $signature"
        checkpoint_arg \
            '.funding.solana += [{source:"Solana Devnet requestAirdrop",transactionSignature:$sig,amountLamports:$amount}]' \
            --arg sig "$signature" --arg amount "$amount"
        sleep 3
        return 0
    fi
    note "Airdrop of $amount lamports unavailable: $(jq -c '.error // .' <<<"$response")"
    return 1
}

solana_lamports="$(solana_balance_lamports "$solana_address")"
if ((solana_lamports < 660240)); then
    request_airdrop_once 1000000000 || true
    solana_lamports="$(solana_balance_lamports "$solana_address")"
fi
if ((solana_lamports < 660240)); then
    request_airdrop_once 100000000 || true
    solana_lamports="$(solana_balance_lamports "$solana_address")"
fi
if ((solana_lamports < 660240)); then
    request_airdrop_once 10000000 || true
    solana_lamports="$(solana_balance_lamports "$solana_address")"
fi

# devnet-pow claims use two signatures, so an existing zero-data System
# account needs its rent floor plus the live two-signature fee. The public Kora
# paymaster contributes only that exact testnet-only gap.
pnpm ts-node --transpile-only scripts/kora-devnet-bootstrap.ts
solana_lamports="$(solana_balance_lamports "$solana_address")"

if ((solana_lamports >= 660240 && solana_lamports < min_solana_lamports)); then
    require_cmd devnet-pow
    reward_lamports=20000000
    # The current faucet claim consumes the live zero-data rent floor plus the
    # two-signature fee before returning the 0.02-SOL reward.
    claim_cost_lamports=660240
    net_reward_lamports="$((reward_lamports - claim_cost_lamports))"
    balance_gap="$((min_solana_lamports - solana_lamports))"
    claims_needed="$(((balance_gap + net_reward_lamports - 1) / net_reward_lamports))"
    target_to_mine="$((claims_needed * reward_lamports))"
    before_slot="$(solana_rpc getSlot '[{"commitment":"confirmed"}]' | jq -er '.result')"
    note "Mining $target_to_mine Devnet lamports through the Foundation-endorsed proof-of-work faucet..."
    devnet-pow --keypair-path "$SOLANA_KEYPAIR_PATH" --url "$SOLANA_RPC_URL" \
        mine -d 3 --reward 0.02 --no-infer --target-lamports "$target_to_mine"
    after_entries="$(solana_rpc getSignaturesForAddress \
        "$(jq -nc --arg address "$solana_address" '[$address,{limit:1000,commitment:"confirmed"}]')" | \
        jq --argjson slot "$before_slot" '[.result[] | select(.slot >= $slot) | {source:"devnet-pow",transactionSignature:.signature,slot,blockTime}]')"
    checkpoint_arg '.funding.solana += $entries' --argjson entries "$after_entries"
    solana_lamports="$(solana_balance_lamports "$solana_address")"
fi

evm_wei="$(evm_balance_wei "$evm_address")"
checkpoint_arg \
    '.funding.lastObserved = {solanaLamports:$sol,evmWei:$evm,checkedAt:(now|todateiso8601)}' \
    --arg sol "$solana_lamports" --arg evm "$evm_wei"

if ((solana_lamports < 660240)); then
    checkpoint_arg '.externalBlockers=["Solana Devnet bootstrap balance is below the live rent and two-signature fee floor."]'
    die "Solana wallet has $solana_lamports lamports. The Devnet PoW rent/fee bootstrap did not reach its safe threshold."
fi
if ((solana_lamports < min_solana_lamports)); then
    checkpoint_arg '.externalBlockers=["Solana Devnet bootstrap balance is below the phase-specific deployment target."]'
    die "Solana wallet has $solana_lamports lamports; target is $min_solana_lamports"
fi
if [[ "$(node -e 'console.log(BigInt(process.argv[1]) >= BigInt(process.argv[2]) ? "yes" : "no")' "$evm_wei" "$min_evm_wei")" != "yes" ]]; then
    checkpoint_arg '.externalBlockers=["Robinhood Testnet deployer requires native test ETH from the official faucet before EVM deployment."]'
    die "Robinhood wallet has $evm_wei wei; claim from https://faucet.testnet.chain.robinhood.com"
fi

checkpoint_apply '.externalBlockers = []'
note "PASS: Solana=$solana_lamports lamports; Robinhood=$evm_wei wei"
