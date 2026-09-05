# Bootstrap deployer funding

Only fund the public addresses in `deployments/bootstrap-wallets.json`.

## Solana Mainnet

- Address: `CvukDFaypgVZzpcksdnJTWJbVgybYeeUZzsBhANXj1ix`
- Asset/network: native SOL on Solana Mainnet
- Received and verified: `5 SOL`
- Current program rent observed from the final-size test binary: about `2.906 SOL`

Five SOL is sufficient for the present deployment estimate but leaves a smaller retry buffer than six SOL. The runner rechecks the live balance and rent before signing.

## Robinhood Mainnet

- Address: `0x53B4fA15cCc227c85a07531Dd4a830a8345a5e7c`
- Asset/network: native ETH on Robinhood Chain Mainnet, chain ID `4663`
- Received and verified: approximately `0.02397 ETH`

## Testnet

- Solana Devnet deployer: `BTvyuzjPozDCLjvhjTsxgBfqeQoKgexEMRyyXvxvvUyN` — funded.
- Robinhood Testnet deployer: `0x131625bbC0c0377812421Ca606dB8725f17ad931` — requires official faucet ETH before the EVM rehearsal can continue.

## Do not send

Do not send STONKS, liquidity, or treasury assets to either bootstrap deployer. The real-asset canary will use an explicitly controlled Solana token account after the bridge infrastructure is deployed and verified.
