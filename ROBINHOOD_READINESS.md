# Robinhood Chain readiness

## Current result

Live readiness checks pass for both LayerZero routes:

- Solana Devnet EID `40168` ↔ Robinhood Testnet EID `40451`, chain ID `46630`.
- Solana Mainnet EID `30168` ↔ Robinhood Mainnet EID `30416`, chain ID `4663`.

`scripts/check-layerzero-readiness.ts` fetches current official LayerZero metadata, verifies both RPC identities, verifies protocol/DVN bytecode or executable accounts, and confirms Robinhood EndpointV2 supports the paired Solana EID. Results are saved as `deployments/testnet-readiness.json` and `deployments/mainnet-readiness.json`.

## Mainnet protocol snapshot

The currently verified Robinhood Mainnet deployment uses:

- EndpointV2: `0x6f475642a6e85809b1c36fa62763669b1b48dd5b`
- SendUln302: `0xc39161c743d0307eb9bcc9fef03eeb9dc4802de7`
- ReceiveUln302: `0xe1844c5d63a9543023008d332bd3d2e6f1fe1043`
- Executor: `0x4208d6e27538189bb48e603d6123a94b8abe0a0b`
- LayerZero Labs DVN: `0xd01ae6905d48315f7be10c7330aecf8360ef5b12`

These are a snapshot, not permanent constants. The production runner refreshes metadata and live code immediately before writes.

## Production configuration

- Required DVN: LayerZero Labs.
- Optional DVNs: Nethermind and Horizen; one optional verification required.
- Confirmations: Robinhood → Solana `15`; Solana → Robinhood `32`.
- Robinhood source explorer: `https://robinhoodchain.blockscout.com`.
- EVM owner/delegate after handoff: temporary Safe `1-of-1`.
- Solana admin/delegate and program upgrade authority after handoff: temporary Squads `1-of-1` vault.

Deployment acceptance requires live configuration readback and `wire --assert`, EVM Blockscout source verification, and a byte-for-byte Solana executable hash match.

## Outstanding launch gate

Infrastructure deployment does not prove transfer behavior with the real asset. A capped mainnet round trip still requires a small amount of STONKS in an operator-controlled Solana token account. Permanent multisig members and higher thresholds must be installed before public launch.
