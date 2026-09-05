import fs from 'fs'
import path from 'path'

const root = path.resolve(__dirname, '..')
const checkpoint = JSON.parse(
    fs.readFileSync(process.env.CHECKPOINT_FILE || path.join(root, 'deployments', 'testnet.json'), 'utf8')
)
const output = path.join(root, 'RUN_RESULT.md')

const value = (input: any): string =>
    input === null || input === undefined || input === '' ? 'PENDING' : String(input)
const bullets = (items: any[]): string =>
    items.length ? items.map((item) => `- ${value(item)}`).join('\n') : '- PENDING'

const messageRows = checkpoint.messages.length
    ? checkpoint.messages
          .map(
              (message: any, index: number) =>
                  `| ${index + 1} | ${message.direction} | ${message.amountUi} | ${value(message.guid)} | ${value(message.sourceTransaction)} | ${value(message.destinationTransaction)} | ${message.status} |`
          )
          .join('\n')
    : '| - | PENDING | - | PENDING | PENDING | PENDING | PENDING |'

const snapshots = checkpoint.messages
    .map(
        (message: any, index: number) =>
            `### Message ${index + 1}: ${message.direction}\n\nBefore:\n\n\`\`\`json\n${JSON.stringify(message.before || null, null, 2)}\n\`\`\`\n\nAfter:\n\n\`\`\`json\n${JSON.stringify(message.after || null, null, 2)}\n\`\`\``
    )
    .join('\n\n')

const transactionItems = [
    ...Object.entries(checkpoint.token.transactions).map(([name, tx]) => `Solana token ${name}: ${value(tx)}`),
    ...checkpoint.solanaAdapter.programDeploymentTransactions.map(
        (tx: string) => `Solana OFT program deployment: ${tx}`
    ),
    `Solana Adapter creation: ${value(checkpoint.solanaAdapter.createTransaction)}`,
    `EVM OFT deployment: ${value(checkpoint.evmOft.deploymentTransaction)}`,
    ...checkpoint.solanaAdapter.configurationTransactions.map((tx: string) => `LayerZero configuration: ${tx}`),
]

const blockers = checkpoint.externalBlockers.length ? bullets(checkpoint.externalBlockers) : '- None'
const document = `# Testnet Run Result

## Final status

${checkpoint.status}

## Network pair

${checkpoint.networkPair}

Robinhood Chain Testnet was selected because live official LayerZero metadata, deployed bytecode, Endpoint EID 40451, Solana EID support, libraries, Executor, DVN pathway, and an Endpoint quote were all verified.

## Wallets and deployments

- Solana wallet: ${checkpoint.wallets.solana}
- EVM wallet: ${checkpoint.wallets.evm}
- Dummy mint: ${value(checkpoint.token.mint)}
- Solana OFT Program: ${value(checkpoint.solanaAdapter.programId)}
- OFT Store: ${value(checkpoint.solanaAdapter.oftStore)}
- Escrow: ${value(checkpoint.solanaAdapter.escrow)}
- EVM OFT: ${value(checkpoint.evmOft.address)}
- EVM EndpointV2: ${checkpoint.evmOft.endpoint}
- EVM source verification: ${value(checkpoint.evmOft.sourceVerification)}${checkpoint.evmOft.sourceVerificationEvidence?.compiler ? ` (${checkpoint.evmOft.sourceVerificationEvidence.compiler}, optimizer ${checkpoint.evmOft.sourceVerificationEvidence.optimizerRuns}, EVM ${checkpoint.evmOft.sourceVerificationEvidence.evmVersion})` : ''}
- Solana executable verification: ${checkpoint.solanaAdapter.sourceVerification?.localHashMatch ? `PASS — local/deployed hash ${checkpoint.solanaAdapter.sourceVerification.binaryHash}` : 'PENDING'}

## Deployment and configuration transactions

${bullets(transactionItems)}

## Cross-chain messages

| # | Direction | Amount (tSTONKS) | GUID | Source transaction | Destination transaction | Status |
|---:|---|---:|---|---|---|---|
${messageRows}

## Before-and-after balances and supplies

${snapshots || 'PENDING'}

## Supply invariants

\`\`\`json
${JSON.stringify(checkpoint.invariants, null, 2)}
\`\`\`

## Run another round trip

\`\`\`bash
ROUNDTRIP_ONLY=1 S2E_AMOUNT=10 E2S_AMOUNT=10 ./run-testnet-e2e.sh
\`\`\`

## Unresolved limitations

${blockers}

The run is complete only after deterministic Solana executable verification, EVM source verification, delivery in both directions, supply-invariant checks, and authority handoff all pass.
`

fs.writeFileSync(output, document, { mode: 0o644 })
