# Wallet and secret inventory

## Testnet bootstrap wallets

- Solana Devnet: `BTvyuzjPozDCLjvhjTsxgBfqeQoKgexEMRyyXvxvvUyN`
- Robinhood Chain Testnet: `0x131625bbC0c0377812421Ca606dB8725f17ad931`

## Mainnet bootstrap wallets

- Solana Mainnet: `CvukDFaypgVZzpcksdnJTWJbVgybYeeUZzsBhANXj1ix`
- Robinhood Chain Mainnet: `0x53B4fA15cCc227c85a07531Dd4a830a8345a5e7c`

These are throwaway bootstrap signers, not permanent bridge administrators.

## Secret storage

The private keys live in macOS Keychain. Materialize the runtime files with:

```bash
./scripts/materialize-keychain-secrets.sh
```

This creates ignored mode-`600` files under `.testnet-secrets/` and `.mainnet-secrets/`. The Solana program keypair establishes the public program ID `6Zxe2WqArgpooREBXPFmyA3fGywgBRccFtYYePZ96tTF`; it is not the eventual upgrade authority.

Never print or copy the private keys into shell commands, `.env`, Git, documentation, tickets, or chat. The wrappers pass every keypair and RPC explicitly and do not change the machine's default Solana wallet.

## Temporary admin containers

The scripts create one Squads v4 multisig/vault and one Safe v1.5.0 per environment. Each starts with its matching bootstrap deployer as the only member/owner and threshold `1`. Their addresses and creation transactions are recorded in the environment checkpoint.
