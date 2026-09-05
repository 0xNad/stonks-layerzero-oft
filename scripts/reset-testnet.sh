#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

[[ "${RESET:-0}" == "1" ]] || die "Refusing reset. Re-run with RESET=1; add RESET_KEYS=1 only to rotate generated mint/buffer keypairs."
require_cmd jq

stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
backup="$ROOT_DIR/deployments/backups/$stamp"
mkdir -p "$backup"
cp "$CHECKPOINT_FILE" "$backup/testnet.json"
cp "$CONFIG_EVIDENCE_FILE" "$backup/testnet-configuration.json"

[[ ! -d "$ROOT_DIR/deployments/robinhood-testnet" ]] || \
    mv "$ROOT_DIR/deployments/robinhood-testnet" "$backup/robinhood-testnet"
[[ ! -d "$ROOT_DIR/deployments/solana-testnet" ]] || \
    mv "$ROOT_DIR/deployments/solana-testnet" "$backup/solana-testnet"
[[ ! -f "$ROOT_DIR/deployments/invariant-result.json" ]] || \
    mv "$ROOT_DIR/deployments/invariant-result.json" "$backup/invariant-result.json"

if [[ "${RESET_KEYS:-0}" == "1" ]]; then
    key_backup="$ROOT_DIR/.testnet-secrets/backups/$stamp"
    mkdir -p "$key_backup"
    chmod 700 "$ROOT_DIR/.testnet-secrets/backups" "$key_backup"
    # The program ID is compiled into Anchor.toml, the Rust declaration, IDL,
    # and ELF, so its protected keypair is intentionally stable across resets.
    for key in tstonks-mint.json oft-program-buffer.json; do
        [[ ! -f "$ROOT_DIR/.testnet-secrets/$key" ]] || mv "$ROOT_DIR/.testnet-secrets/$key" "$key_backup/$key"
    done
fi

checkpoint_apply '
  .status="RESET_READY" |
  .token.mint=null |
  .token.deployerAta=null |
  .token.transactions={createMint:null,createAta:null,mintSupply:null,revokeAuthorities:null} |
  .token.mintAuthority="PENDING" |
  .token.freezeAuthority="PENDING" |
  .token.supplyBeforeBridgeRaw=null |
  .solanaAdapter.programId=null |
  .solanaAdapter.programDeploymentTransactions=[] |
  .solanaAdapter.oftStore=null |
  .solanaAdapter.escrow=null |
  .solanaAdapter.createTransaction=null |
  .solanaAdapter.configurationTransactions=[] |
  .evmOft.address=null |
  .evmOft.deploymentTransaction=null |
  .evmOft.addressPreviouslyObserved=false |
  .evmOft.sourceVerification="PENDING" |
  .messages=[] |
  .invariants={status:"PENDING",normalizedEscrowShared:null,evmSupplyShared:null,solanaSupplyBeforeRaw:null,solanaSupplyAfterRaw:null,solanaUserRaw:null,solanaEscrowRaw:null,checkedAt:null} |
  .externalBlockers=[]'

config_tmp="$(mktemp "$CONFIG_EVIDENCE_FILE.tmp.XXXXXX")"
jq '.status="EXPECTED_VALIDATED_NOT_YET_WIRED" | .updatedAt=(now|todateiso8601) | .applicationReadback={evmOft:null,solanaOftStore:null,peers:null,sendLibraries:null,receiveLibraries:null,sendConfigs:null,receiveConfigs:null,enforcedOptions:null,assertCommandPassed:false,rawConfigGetOutput:null,readAt:null}' \
    "$CONFIG_EVIDENCE_FILE" >"$config_tmp"
mv "$config_tmp" "$CONFIG_EVIDENCE_FILE"

note "Reset checkpoint created. Prior public evidence is recoverable at $backup. On-chain deployments were not closed."
