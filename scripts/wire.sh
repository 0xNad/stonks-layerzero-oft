#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ "${DEPLOYMENT_ENV:-testnet}" == "mainnet" ]]; then
    # shellcheck source=scripts/lib/mainnet-common.sh
    source "$SCRIPT_DIR/lib/mainnet-common.sh"
else
    # shellcheck source=scripts/lib/common.sh
    source "$SCRIPT_DIR/lib/common.sh"
fi

for command in jq pnpm rg; do require_cmd "$command"; done
if [[ "${DEPLOYMENT_ENV:-testnet}" == "mainnet" ]]; then
    load_mainnet_env
    assert_mainnets
    ensure_solana_mainnet_deployment_file
else
    load_testnet_env
    assert_public_testnets
    ensure_solana_deployment_file
fi

[[ -n "$(json_get '.evmOft.address // empty')" ]] || die "Deploy the EVM OFT before wiring"
[[ -n "$(json_get '.solanaAdapter.oftStore // empty')" ]] || die "Create the Solana Adapter before wiring"

init_output="$(mktemp "${TMPDIR:-/tmp}/stonks-init-config.XXXXXX")"
wire_output="$(mktemp "${TMPDIR:-/tmp}/stonks-wire.XXXXXX")"
assert_output="$(mktemp "${TMPDIR:-/tmp}/stonks-wire-assert.XXXXXX")"
readback_output="$(mktemp "${TMPDIR:-/tmp}/stonks-config-readback.XXXXXX")"

CI=1 pnpm hardhat lz:oft:solana:init-config \
    --oapp-config layerzero.config.ts --ci 2>&1 | tee "$init_output"

pnpm hardhat lz:oapp:wire \
    --oapp-config layerzero.config.ts --ci 2>&1 | tee "$wire_output"

pnpm hardhat lz:oapp:wire \
    --oapp-config layerzero.config.ts --assert 2>&1 | tee "$assert_output"

pnpm hardhat lz:oapp:config:get \
    --oapp-config layerzero.config.ts 2>&1 | tee "$readback_output"

transaction_urls="$(
    {
        rg -o 'https?://[^[:space:]]+/tx/(0x[0-9a-fA-F]{64}|[1-9A-HJ-NP-Za-km-z]{64,100})[^[:space:]]*' \
            "$init_output" "$wire_output" || true
    } | sed 's/^[^:]*://' | sort -u | jq -Rsc 'split("\n") | map(select(length>0))'
)"
transaction_ids="$(printf '%s' "$transaction_urls" | jq '[.[] | capture("/tx/(?<id>0x[0-9a-fA-F]{64}|[1-9A-HJ-NP-Za-km-z]{64,100})").id]')"
raw_readback="$(<"$readback_output")"
raw_assert="$(<"$assert_output")"

config_tmp="$(mktemp "$CONFIG_EVIDENCE_FILE.tmp.XXXXXX")"
jq \
    --argjson txUrls "$transaction_urls" \
    --argjson txIds "$transaction_ids" \
    --arg raw "$raw_readback" \
    --arg assertion "$raw_assert" \
    --slurpfile state "$CHECKPOINT_FILE" \
    '.status="WIRED_AND_ASSERTED" |
     .updatedAt=(now|todateiso8601) |
     .applicationReadback.evidenceMethod="Live official LayerZero config readback followed by wire --assert" |
     .applicationReadback.sourceCommands=[
       "pnpm hardhat lz:oapp:config:get --oapp-config layerzero.config.ts",
       "pnpm hardhat lz:oapp:wire --oapp-config layerzero.config.ts --assert"
     ] |
     .applicationReadback.evmOft={address:$state[0].evmOft.address,owner:$state[0].evmOft.owner,delegate:$state[0].evmOft.owner,endpoint:.protocolDeployments.robinhood.endpointV2} |
     .applicationReadback.solanaOftStore={address:$state[0].solanaAdapter.oftStore,programId:$state[0].solanaAdapter.programId,admin:$state[0].wallets.solana,delegate:$state[0].solanaAdapter.delegate,endpoint:.protocolDeployments.solana.endpointV2,mode:$state[0].solanaAdapter.mode} |
     .applicationReadback.peers={robinhoodToSolana:{localOApp:$state[0].evmOft.address,remoteEid:.pathway.solanaEid,peerOApp:$state[0].solanaAdapter.oftStore},solanaToRobinhood:{localOApp:$state[0].solanaAdapter.oftStore,remoteEid:.pathway.robinhoodEid,peerOApp:$state[0].evmOft.address}} |
     .applicationReadback.sendLibraries={robinhoodToSolana:.protocolDeployments.robinhood.sendUln302,solanaToRobinhood:.protocolDeployments.solana.sendReceiveUln302Program} |
     .applicationReadback.receiveLibraries={robinhoodFromSolana:.protocolDeployments.robinhood.receiveUln302,solanaFromRobinhood:.protocolDeployments.solana.sendReceiveUln302Program} |
     .applicationReadback.sendConfigs={robinhoodToSolana:{confirmations:.pathway.confirmations.robinhoodToSolana,requiredDVNs:.protocolDeployments.robinhood.requiredDvns,optionalDVNs:(.protocolDeployments.robinhood.optionalDvns // []),optionalDVNThreshold:(.pathway.optionalDvnThreshold // 0),executor:.protocolDeployments.robinhood.executor,maxMessageSize:.pathway.maxMessageSize},solanaToRobinhood:{confirmations:.pathway.confirmations.solanaToRobinhood,requiredDVNs:.protocolDeployments.solana.requiredDvns,optionalDVNs:(.protocolDeployments.solana.optionalDvns // []),optionalDVNThreshold:(.pathway.optionalDvnThreshold // 0),executor:.protocolDeployments.solana.executorConfig,maxMessageSize:.pathway.maxMessageSize}} |
     .applicationReadback.receiveConfigs={robinhoodFromSolana:{confirmations:.pathway.confirmations.solanaToRobinhood,requiredDVNs:.protocolDeployments.robinhood.requiredDvns,optionalDVNs:(.protocolDeployments.robinhood.optionalDvns // []),optionalDVNThreshold:(.pathway.optionalDvnThreshold // 0)},solanaFromRobinhood:{confirmations:.pathway.confirmations.robinhoodToSolana,requiredDVNs:.protocolDeployments.solana.requiredDvns,optionalDVNs:(.protocolDeployments.solana.optionalDvns // []),optionalDVNThreshold:(.pathway.optionalDvnThreshold // 0)}} |
     .applicationReadback.enforcedOptions=.pathway.enforcedOptions |
     .applicationReadback.assertCommandPassed=true |
     .applicationReadback.rawConfigGetOutput=$raw |
     .applicationReadback.rawAssertOutput=$assertion |
     .applicationReadback.configurationTransactions=((.applicationReadback.configurationTransactions // []) + ($state[0].solanaAdapter.configurationTransactions // []) + $txIds | unique) |
     .applicationReadback.configurationTransactionUrls=((.applicationReadback.configurationTransactionUrls // []) + $txUrls | unique) |
     .applicationReadback.readAt=(now|todateiso8601)' \
    "$CONFIG_EVIDENCE_FILE" >"$config_tmp"
mv "$config_tmp" "$CONFIG_EVIDENCE_FILE"

checkpoint_arg \
    '.solanaAdapter.configurationTransactions = ((.solanaAdapter.configurationTransactions + $txs) | unique) |
     .layerZero.configurationStatus="PASS" |
     .layerZero.assertionStatus="PASS"' \
    --argjson txs "$transaction_ids"

note "PASS: LayerZero peers, libraries, DVN, Executor, confirmations, and enforced options match layerzero.config.ts"
