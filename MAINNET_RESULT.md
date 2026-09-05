# Mainnet Deployment Result

## Final status

LIVE — DEPLOYED, WIRED, VERIFIED, ADMIN-HANDOFF AND ROUND-TRIP CANARY COMPLETE

## Canonical asset

- STONKS mint: stonksUpymwbn1rBBpZmd1u92ydJ2asGw1y7capGMzW
- Token program: TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA
- Solana decimals: 9
- Robinhood decimals: 18
- Shared decimals: 6
- Mint authority: revoked
- Freeze authority: revoked

## Live deployments

- Solana OFT program: 6Zxe2WqArgpooREBXPFmyA3fGywgBRccFtYYePZ96tTF
- Solana program deployment transaction: 4FC14ToBB9V411sVLXgZ5DswYS6bdoQxW1KejxkeptCGU8MM5bLH34fA1LLUj94cNuxRypYvLqiG2RR5fLJhq74e
- Solana OFT Store: HR7jWZ9h87CXyWppZbmvdHxwpZti2ru5txSr7LfmS9XM
- Solana escrow: HEfjShoi4xbcgvFBfaKifzih1c2LsGfr1trUjaAuFc7D
- Robinhood OFT: 0x69C66594D67d47A480364B950ec9d6f674573727
- Robinhood deployment transaction: 0x46ea7f5fa1d4fcd04b188d2d1e8281a01e6a304686ec9faca85a8e82a482d9ec
- Robinhood initial and current supply: zero
- Robinhood public mint function: absent

## Verification

- Solana local/deployed executable hash: PASS — 08638531860e9bf3b394ae980511d5cac9a0cffbaa7cd2cad5ee509148665925
- Robinhood source: PASS — Sourcify exact_match
- Robinhood verification record: https://sourcify.dev/server/v2/contract/4663/0x69C66594D67d47A480364B950ec9d6f674573727
- LayerZero configuration assertion: PASS

## LayerZero security policy

- Required DVN: LayerZero Labs
- Optional DVNs: Nethermind, Horizen
- Optional DVN threshold: 1
- Robinhood to Solana confirmations: 15
- Solana to Robinhood confirmations: 32

## Temporary administration

- Solana Squads multisig: E3h2JnuDVxR72jU7g4bHJWpgH4wNZMDBLh3BuFuwFLPc
- Solana Squads vault: 95u34bCkNg8tEtiJuENfLKzKrgJtqv8qwYzJW3vJbQ9V
- Solana threshold: 1-of-1
- Robinhood Safe: 0x412E5001B698371f9F34b59fC13e7e8C5A9F3A27
- Robinhood Safe threshold: 1-of-1

Authority readbacks:

- Solana program upgrade authority: PASS
- Solana OFT admin: PASS
- Solana LayerZero delegate: PASS
- Robinhood OFT owner: PASS
- Robinhood LayerZero delegate: PASS

## Mainnet round-trip canary

- Funding swap: 3T2FLDPFDrYgYC7VMXxvBDvz9QzpR4ZBbcUDnv6MJgpP21P4jacgp12ajWm3uVQqkY48hZNW6v6X53pHxeqGsLpx
- STONKS acquired: 1.03243018
- Canary status: PASS
- Supply invariants: PASS
- Final Solana escrow raw: 0
- Final Robinhood supply raw: 0

| Direction     | Amount | GUID                                                               | Source transaction                                                                       | Destination transaction                                                                  | Status    |
| ------------- | -----: | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------- |
| SOLANA_TO_EVM |      1 | 0x62f525848e301b2824f18982da35aeb0d0e66ba4ea51b50513c3ba4f7a8c1a99 | 2Z4xHAjnT2trGTFXtLXzNyHt9U1ByoQfJuuHuDrhbaGZtJ67TpsUsEHLGztbm57fvwn1nSHoenjRtuByupsH852k | 0xf82092fd3af676025c5d026bdbda98b71b6f4b7379e966bcdb8ba5785096e86d                       | DELIVERED |
| EVM_TO_SOLANA |      1 | 0x726de72734641fb2d1f8d609ae21abba8adf96e486d470d94ae4d8096a5c7735 | 0x84a99af15f21e60511ec325fd05508cf91c02de6a4409344af3234ba2d3c726b                       | 5WVeqhQDwxiwiueYPtZwUQhMyih1kodniB1uQpTD8HCKXUpJgoFUocmmMoHyMFvxbH2czLa1Bs9Hroo7JLu8Le8Q | DELIVERED |

## Remaining launch gates

- Add permanent owners, raise both multisig thresholds, verify them on-chain, and remove the throwaway deployers before public launch.

The funded mainnet canary delivered in both directions and the independent supply invariants passed.
