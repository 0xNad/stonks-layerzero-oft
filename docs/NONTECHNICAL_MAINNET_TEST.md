# Self-serve STONKS bridge test with a coding agent

This test is fully self-serve. A STONKS team member funds two throwaway wallets created by their own local coding agent. Their agent signs and submits the real LayerZero transfer in both directions. No bridge operator, admin access, or hosted website is required.

The test uses real mainnet assets. Cap it at exactly 1 STONKS.

## Safety rules

- Use fresh throwaway wallets created locally for this test.
- Never paste a seed phrase, private key, recovery phrase, or wallet JSON into chat.
- The coding agent must never print, upload, commit, or transmit wallet secrets.
- Store test keys only in the ignored `.tester-secrets/` directory with restrictive permissions.
- Do not use a treasury, multisig, or permanent personal wallet as the signing wallet.
- The agent may execute only the two OFT transfer operations. It must not deploy, upgrade, wire, pause, change ownership, or perform an admin operation.
- The agent must verify every network and deployment address before signing.
- The agent must obtain a read-only fee quote and wait for the exact confirmation phrase before each transaction.

## Official deployment

- Repository: `https://github.com/0xNad/stonks-layerzero-oft`
- Canonical Solana STONKS mint: `stonksUpymwbn1rBBpZmd1u92ydJ2asGw1y7capGMzW`
- Solana token program: `TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`
- Solana OFT program: `6Zxe2WqArgpooREBXPFmyA3fGywgBRccFtYYePZ96tTF`
- Solana OFT Store: `HR7jWZ9h87CXyWppZbmvdHxwpZti2ru5txSr7LfmS9XM`
- Solana escrow: `HEfjShoi4xbcgvFBfaKifzih1c2LsGfr1trUjaAuFc7D`
- Robinhood STONKS contract: `0x69C66594D67d47A480364B950ec9d6f674573727`
- Solana LayerZero endpoint ID: `30168`
- Robinhood LayerZero endpoint ID: `30416`
- Robinhood chain ID: `4663`
- Robinhood RPC: `https://rpc.mainnet.chain.robinhood.com`
- Robinhood explorer: `https://robinhoodchain.blockscout.com`

The agent must compare these values with `deployments/mainnet.json` and live chain readbacks before signing.

## Step-by-step instructions for the team member

### 1. Start a local coding agent

Open Codex, Claude Code, or another coding agent that can use a local terminal and access the internet. Paste the complete prompt at the end of this guide.

### 2. Receive two public funding addresses

The agent will:

1. clone the public repository;
2. inspect the deployment evidence;
3. create `.tester-secrets/` locally;
4. generate a throwaway Solana wallet;
5. generate a throwaway EVM wallet; and
6. show only their public addresses.

The private keys remain in local ignored files. The member never sends them to anybody.

### 3. Fund the wallets

Send to the new Solana public address:

- exactly 1 STONKS; and
- enough SOL for the quoted LayerZero and Solana transaction fees.

Send enough Robinhood Chain ETH to the new EVM public address for the quoted return fee and EVM transaction fee.

Use `0.01 SOL` and `0.002 ETH` as cautious starting allowances. After funding creates the required token account, the agent obtains current read-only quotes and requests a top-up if either allowance is insufficient. Current quotes always control, and leftovers can be refunded.

Tell the agent `funded`. The agent independently verifies all three balances on-chain.

### 4. Send 1 STONKS from Solana to Robinhood

The agent performs a read-only LayerZero quote and displays:

- `Solana -> Robinhood`;
- amount: `1 STONKS`;
- the two throwaway public addresses;
- the live native fee;
- the canonical Solana mint; and
- the Robinhood OFT contract.

If everything is correct, reply exactly:

`CONFIRM SOLANA TO ROBINHOOD 1 STONKS`

The agent then signs with the local throwaway Solana key, submits the OFT send, and waits for LayerZero status `DELIVERED`.

### 5. Verify receipt on Robinhood

The agent verifies that the throwaway EVM wallet owns exactly 1 STONKS issued by:

`0x69C66594D67d47A480364B950ec9d6f674573727`

It reports:

- the Solana source transaction;
- the Robinhood destination transaction; and
- the LayerZero message link.

### 6. Send 1 STONKS from Robinhood back to Solana

The agent performs another read-only quote and displays the reverse transfer details.

If everything is correct, reply exactly:

`CONFIRM ROBINHOOD TO SOLANA 1 STONKS`

The agent signs with the local throwaway EVM key, submits the OFT send, and waits for `DELIVERED`.

### 7. Verify the completed round trip

The agent verifies and reports:

- exactly 1 canonical STONKS returned to the throwaway Solana wallet;
- the throwaway EVM STONKS balance returned to zero;
- both LayerZero messages are `DELIVERED`;
- the canonical Solana supply did not change;
- the Solana escrow and Robinhood OFT supply moved consistently on both legs; and
- all four chain transactions and both LayerZero message links.

### 8. Return leftovers

Give the agent normal Solana and EVM refund addresses if desired. The agent must show the refund amounts and request separate confirmation before returning leftover SOL or ETH.

The agent must ask before deleting `.tester-secrets/`. Deleting it permanently destroys access to the throwaway wallets.

## Copy-and-paste prompt for the coding agent

```text
Run a fully self-serve, capped STONKS mainnet bridge round-trip for me.

Repository:
https://github.com/0xNad/stonks-layerzero-oft

First clone the repository and read README.md, MAINNET_RESULT.md, deployments/mainnet.json, layerzero.config.ts, and docs/NONTECHNICAL_MAINNET_TEST.md in full.

Use exactly 1 STONKS. You are authorized to create two local throwaway wallets and, only after the exact confirmations below, send 1 STONKS from Solana to Robinhood Chain and then send the same 1 STONKS back to Solana.

Non-negotiable safety rules:
- Work only in this repository and use the recorded mainnet deployment.
- Create fresh Solana and EVM throwaway wallets under .tester-secrets/.
- Add .tester-secrets/ to .git/info/exclude as a second safeguard.
- Set directory mode 700 and secret file mode 600.
- Never display, upload, commit, log, or transmit any private key, seed phrase, recovery phrase, mnemonic, or wallet JSON content.
- Show me only public addresses.
- Never ask me to paste a private key into chat.
- Do not modify any tracked file or deployment checkpoint.
- Do not deploy, upgrade, wire, pause, configure peers or DVNs, change owners or delegates, or invoke any admin operation.
- The only authorized writes are the two LayerZero OFT send transactions after my exact confirmation and separately confirmed refund transactions.
- Refuse to sign if any network, address, bytecode, balance, simulation, or quote check fails.

Verify before funding:
- Solana mainnet genesis is 5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d.
- Robinhood eth_chainId is 0x1237, decimal 4663.
- Canonical mint is stonksUpymwbn1rBBpZmd1u92ydJ2asGw1y7capGMzW.
- Solana OFT program is 6Zxe2WqArgpooREBXPFmyA3fGywgBRccFtYYePZ96tTF.
- Solana OFT Store is HR7jWZ9h87CXyWppZbmvdHxwpZti2ru5txSr7LfmS9XM.
- Solana escrow is HEfjShoi4xbcgvFBfaKifzih1c2LsGfr1trUjaAuFc7D.
- Robinhood OFT is 0x69C66594D67d47A480364B950ec9d6f674573727.
- LayerZero EIDs are 30168 for Solana and 30416 for Robinhood.

Prepare the repository and silently create the wallets. Then give me:
1. the throwaway Solana public address;
2. the throwaway EVM public address;
3. the initial funding request: exactly 1 STONKS, 0.01 SOL, and 0.002 Robinhood ETH; and
4. public explorer links for both wallets.

Wait until I reply funded. Verify the balances independently, obtain current read-only LayerZero quotes for both directions, and request a top-up if the funded gas allowance is insufficient.

Before the first send, show the complete Solana-to-Robinhood transaction summary and wait until I reply exactly:
CONFIRM SOLANA TO ROBINHOOD 1 STONKS

Use the repository's LayerZero OFT send task directly with my throwaway Solana signer, destination EID 30416, and my throwaway EVM address. Do not use an operator-specific wrapper or change deployments/mainnet.json. Wait for DELIVERED and verify the EVM token balance.

Before the return send, show the complete Robinhood-to-Solana transaction summary and wait until I reply exactly:
CONFIRM ROBINHOOD TO SOLANA 1 STONKS

Use the repository's LayerZero OFT send task directly with my throwaway EVM signer, destination EID 30168, and my throwaway Solana address. Wait for DELIVERED.

Finally verify the round-trip balances and supply invariants. Give me all four chain transaction links, both LayerZero message links, fees paid, starting balances, final balances, and an explicit PASS or FAIL. Do not delete the throwaway keys or refund leftovers without separate confirmation.
```

## Pass criteria

The test passes only when:

- the member funded and controlled the test wallets;
- no wallet secret was exposed;
- the member explicitly confirmed both bridge sends;
- both LayerZero messages say `DELIVERED`;
- exactly 1 STONKS arrived on Robinhood and returned to Solana;
- the balance and supply invariants pass; and
- the agent provides all transaction and message links.

This is self-serve agent-assisted bridging. A hosted wallet page is optional convenience, not a testing requirement.
