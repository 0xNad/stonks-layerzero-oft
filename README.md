# STONKS LayerZero V2 bridge

This repository implements a LayerZero V2 lockbox bridge between the canonical STONKS SPL token on Solana and a burn/mint OFT on Robinhood Chain.

- Canonical Solana mint: `stonksUpymwbn1rBBpZmd1u92ydJ2asGw1y7capGMzW`
- Solana side: existing STONKS is locked in an OFT Adapter escrow; the SPL mint authority stays revoked.
- Robinhood side: `StonksOFT` starts with zero supply and can mint only after authenticated LayerZero delivery. Returning tokens burns the EVM supply and releases the corresponding escrowed STONKS.
- Local decimals: Solana `9`, Robinhood `18`; shared decimals: `6`.

## Networks and guards

Every write wrapper checks the live network identity before signing.

| Environment | Solana                        | Robinhood        | LayerZero EIDs     |
| ----------- | ----------------------------- | ---------------- | ------------------ |
| Test        | Devnet genesis `EtWTR…PkrZBG` | chain ID `46630` | `40168` ↔ `40451` |
| Production  | Mainnet genesis `5eykt…w2N9d` | chain ID `4663`  | `30168` ↔ `30416` |

Testnet uses a fixed-supply `tSTONKS` rehearsal mint. Mainnet scripts accept only the canonical STONKS mint and fail if its token program, decimals, mint authority, or freeze authority differ from the recorded safety assumptions.

## Security configuration

The production pathway is pinned to:

- required DVN: LayerZero Labs;
- optional DVNs: Nethermind and Horizen, threshold `1`;
- confirmations: Robinhood → Solana `15`, Solana → Robinhood `32`;
- enforced receive options: `200,000` Solana compute units plus `2,039,280` lamports for recipient token-account rent, and `80,000` Robinhood EVM gas.

The scripts read the configuration back from both chains and require LayerZero's `wire --assert` to pass. They do not rely on the configuration transaction merely being accepted.

## Administration

Bootstrap administration is intentionally temporary and follows the requested `1-of-1` policy:

- Squads v4 on Solana holds the Adapter admin/delegate and program upgrade authority;
- Safe v1.5.0 on Robinhood holds the EVM OFT owner/delegate.

The deployer is the sole initial member/owner. Before public launch, add permanent owners, raise both thresholds, verify the changes on-chain, and remove the throwaway deployers.

## Testnet proof

Run or resume the full rehearsal:

```bash
./run-testnet-e2e.sh
```

The run deploys the Solana program and Adapter, verifies its executable hash, deploys and source-verifies the zero-supply EVM OFT, wires and asserts both pathways, completes messages in both directions, verifies supply invariants, and hands authority to the test admin containers.

Current public state and evidence:

- `deployments/testnet.json`
- `deployments/testnet-configuration.json`
- `deployments/invariant-result.json`
- `RUN_RESULT.md`

`RUN_RESULT.md` must not say PASS until both directions have delivered and the independent supply checks pass.

## Mainnet deployment

The authorized resumable production pipeline is:

```bash
./run-mainnet-deploy.sh
```

It refreshes official LayerZero metadata and live chain identities, creates the two admin containers, deploys the Solana program and Adapter, proves the local/deployed executable hash match, deploys and verifies the Robinhood contract source, wires and asserts both pathways, then hands all configured authority to Squads and Safe.

The mainnet checkpoint is `deployments/mainnet.json`; detailed readback is `deployments/mainnet-configuration.json`, and the operator-facing summary is `MAINNET_RESULT.md`. Every irreversible address is checkpointed, and a rerun adopts a matching deployment instead of creating a duplicate.

A capped 1 STONKS mainnet round-trip canary has delivered from Solana to Robinhood and back, and the independent supply invariants passed. The transactions and balance evidence are recorded in `MAINNET_RESULT.md` and `deployments/mainnet.json`. This proves the live bridge path; it is not a substitute for replacing the temporary owners and raising both multisig thresholds before public launch. No treasury or liquidity funds should be sent to either bootstrap deployer.

For a capped self-serve test, a nontechnical STONKS team member can give [`docs/NONTECHNICAL_MAINNET_TEST.md`](docs/NONTECHNICAL_MAINNET_TEST.md) to their local coding agent. Their agent creates and controls throwaway wallets, executes both bridge directions after explicit confirmations, and records the evidence without exposing private keys. No bridge operator is involved.

## Source and reproducibility

The Solana program and operational tasks are derived from LayerZero's official `devtools/examples/oft-solana` at commit `4973ba8bef7b0fdf7268469abea3ea50dbd4bbd8`, example version `0.12.11`. The EVM contract contains no public mint function and has automated zero-initial-supply tests.

`scripts/build-solana-verifiable.sh` creates the deterministic Solana build in the pinned verifier image. `scripts/verify-solana-source.sh` requires its executable hash to equal the deployed program hash. A public OtterSec/Solana verified-build badge remains unavailable while this GitHub repository is private; the local hash proof is still recorded in the deployment checkpoint.

Fresh deployments reserve `600,000` bytes for program data. The current deterministic executable is smaller, leaving bounded room for a future audited upgrade without materially overfunding rent.

## Secret handling

Private keys are stored in macOS Keychain. `scripts/materialize-keychain-secrets.sh` writes them only to ignored `.testnet-secrets/` and `.mainnet-secrets/` directories with mode `700` and files with mode `600`. Never paste keys into `.env`, documentation, issues, transactions, or Git history.

See `TOOL_VERSIONS.md`, `TESTNET_ACCESS.md`, `FUNDING.md`, and `ROBINHOOD_READINESS.md` for the exact operational inventory.
