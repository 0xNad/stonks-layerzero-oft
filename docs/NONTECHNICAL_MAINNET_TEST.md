# STONKS bridge test for a nontechnical team member

This is an **operator-assisted mainnet acceptance test** using 1 STONKS. It lets a STONKS team member receive the bridged token on Robinhood Chain and receive the canonical token back on Solana without handling code or sharing wallet secrets.

The bridge contracts are live, but there is not yet a public wallet-connected bridge page. The operator signs the two bridge transactions in this test. The team member only uses Phantom and MetaMask or Rabby for ordinary wallet actions.

## Safety rules

- Use exactly 1 STONKS.
- Never share a seed phrase, private key, recovery phrase, JSON key file, or screen showing one.
- The operator needs only the member's two **public receiving addresses**.
- Confirm the operator and all addresses in the STONKS team's normal private communication channel before moving tokens.
- Stop if a wallet displays a different token contract, network, or amount from this guide.
- This test proves the live bridge path. It is not approval for a public launch while the admin multisigs remain temporary 1-of-1.

## Official addresses

- Canonical Solana STONKS mint: `stonksUpymwbn1rBBpZmd1u92ydJ2asGw1y7capGMzW`
- Solana OFT Store: `HR7jWZ9h87CXyWppZbmvdHxwpZti2ru5txSr7LfmS9XM`
- Solana escrow: `HEfjShoi4xbcgvFBfaKifzih1c2LsGfr1trUjaAuFc7D`
- Robinhood STONKS contract: `0x69C66594D67d47A480364B950ec9d6f674573727`
- Current test operator EVM address: `0x53B4fA15cCc227c85a07531Dd4a830a8345a5e7c`

## Before the call

The team member needs:

1. Phantom or Solflare with a Solana mainnet wallet.
2. MetaMask or Rabby with an EVM wallet.
3. A small amount of ETH on Robinhood Chain for one normal token transfer. The operator can fund this test gas if necessary.
4. A live call or private STONKS team chat with the bridge operator.

Do not send either wallet's private key to the operator. Public wallet addresses are safe to share.

## Part 1: Prepare Robinhood Chain

1. Open MetaMask or Rabby.
2. Add a network with these values:
   - Network name: `Robinhood Chain`
   - RPC URL: `https://rpc.mainnet.chain.robinhood.com`
   - Chain ID: `4663`
   - Currency symbol: `ETH`
   - Block explorer: `https://robinhoodchain.blockscout.com`
3. Switch the wallet to Robinhood Chain.
4. Import a custom token using:
   - Token contract: `0x69C66594D67d47A480364B950ec9d6f674573727`
   - Symbol: `STONKS`
   - Decimals: `18`
5. Copy the wallet's public `0x...` address.
6. Open Phantom or Solflare and copy the Solana public address.
7. Send both public addresses to the operator in the agreed STONKS team channel.

## Part 2: Receive 1 STONKS on Robinhood Chain

1. The operator reads the EVM address back to the team member and confirms it character by character at the beginning and end.
2. The operator bridges exactly 1 STONKS from Solana to that EVM address.
3. The operator sends the Solana source transaction and LayerZero Scan links to the member.
4. Open `https://layerzeroscan.com` and paste the source transaction into the search box.
5. Wait for the message to show `Delivered`.
6. Open MetaMask or Rabby on Robinhood Chain.
7. Confirm that the imported STONKS token shows a balance of exactly 1 STONKS.
8. Open the address on `https://robinhoodchain.blockscout.com` and confirm the same token balance.

Do not continue if the LayerZero message is not delivered or the received token contract differs from the official Robinhood STONKS contract above.

## Part 3: Return the token to Solana

The current test is operator-assisted because there is no public bridge page yet.

1. Confirm that the EVM wallet has enough Robinhood Chain ETH for one normal token transfer.
2. In MetaMask or Rabby, select STONKS and press **Send**.
3. Enter the current test operator EVM address:
   `0x53B4fA15cCc227c85a07531Dd4a830a8345a5e7c`
4. Enter exactly `1` STONKS.
5. Review the network, token contract, destination and amount, then approve the transaction.
6. Send the resulting transaction link to the operator.
7. The operator confirms receipt and bridges exactly 1 STONKS from Robinhood Chain to the member's Solana address.
8. The operator sends the Robinhood source transaction and LayerZero Scan links to the member.
9. Search the source transaction on `https://layerzeroscan.com` and wait for `Delivered`.
10. Open Phantom or Solflare and confirm receipt of 1 canonical STONKS.
11. If the token is hidden, use the wallet's token-management screen and verify the mint is exactly:
    `stonksUpymwbn1rBBpZmd1u92ydJ2asGw1y7capGMzW`

## Pass criteria

The test passes only when all of the following are true:

- The Solana-to-Robinhood LayerZero message says `Delivered`.
- The member receives exactly 1 STONKS from the official Robinhood contract.
- The Robinhood-to-Solana LayerZero message says `Delivered`.
- The member receives exactly 1 STONKS from the canonical Solana mint.
- Both source and destination transactions are recorded in the test notes.
- No seed phrase or private key was shared.

## What this does and does not prove

This verifies real mainnet delivery, wallet visibility and the round-trip asset path. It does **not** test self-service bridge usability because the operator signs the crosschain sends.

A genuinely self-service nontechnical test requires either:

- listing STONKS on the Stargate frontend; or
- deploying a STONKS bridge page with Phantom/Solflare and MetaMask/Rabby connections.

The test operator should record the member's two public addresses, both source transactions, both destination transactions, both LayerZero message links, start and finish balances, and the final pass/fail result.
