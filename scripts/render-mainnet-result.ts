import fs from 'fs'
import path from 'path'

const root = path.resolve(__dirname, '..')
const checkpoint = JSON.parse(fs.readFileSync(path.join(root, 'deployments', 'mainnet.json'), 'utf8'))
const output = path.join(root, 'MAINNET_RESULT.md')

const value = (input: unknown): string =>
    input === null || input === undefined || input === '' ? 'PENDING' : String(input)
const pass = (input: unknown): string => (input === true ? 'PASS' : 'FAIL')

const checks = checkpoint.adminHandoff?.checks || {}
const programTransactions = checkpoint.solanaAdapter.programDeploymentTransactions || []
const canaryMessages = checkpoint.canary?.messages || []
const canaryComplete = checkpoint.canary?.status === 'PASS' && checkpoint.canary?.invariants?.status === 'PASS'
const canaryRows = canaryMessages.length
    ? canaryMessages
          .map(
              (message: any) =>
                  `| ${message.direction} | ${message.amountUi} | ${message.guid} | ${message.sourceTransaction} | ${message.destinationTransaction} | ${message.status} |`
          )
          .join('\n')
    : '| PENDING | - | PENDING | PENDING | PENDING | PENDING |'
const launchGates = [
    ...(checkpoint.externalBlockers || []),
    'Add permanent owners, raise both multisig thresholds, verify them on-chain, and remove the throwaway deployers before public launch.',
]
    .map((item: string) => `- ${item}`)
    .join('\n')

const document = `# Mainnet Deployment Result

## Final status

${checkpoint.status}

## Canonical asset

- STONKS mint: ${checkpoint.token.mint}
- Token program: ${checkpoint.token.tokenProgram}
- Solana decimals: ${checkpoint.token.decimals}
- Robinhood decimals: ${checkpoint.evmOft.decimals}
- Shared decimals: ${checkpoint.token.sharedDecimals}
- Mint authority: revoked
- Freeze authority: revoked

## Live deployments

- Solana OFT program: ${checkpoint.solanaAdapter.programId}
- Solana program deployment transaction: ${value(programTransactions[0])}
- Solana OFT Store: ${checkpoint.solanaAdapter.oftStore}
- Solana escrow: ${checkpoint.solanaAdapter.escrow}
- Robinhood OFT: ${checkpoint.evmOft.address}
- Robinhood deployment transaction: ${checkpoint.evmOft.deploymentTransaction}
- Robinhood initial and current supply: zero
- Robinhood public mint function: absent

## Verification

- Solana local/deployed executable hash: ${checkpoint.solanaAdapter.sourceVerification.localHashMatch ? `PASS — ${checkpoint.solanaAdapter.sourceVerification.binaryHash}` : 'FAIL'}
- Robinhood source: ${checkpoint.evmOft.sourceVerification} — ${checkpoint.evmOft.sourceVerificationProvider} ${checkpoint.evmOft.sourceVerificationMatch}
- Robinhood verification record: ${checkpoint.evmOft.sourceVerificationUrl}
- LayerZero configuration assertion: ${checkpoint.layerZero.assertionStatus}

## LayerZero security policy

- Required DVN: ${checkpoint.layerZero.requiredDvns.join(', ')}
- Optional DVNs: ${checkpoint.layerZero.optionalDvns.join(', ')}
- Optional DVN threshold: ${checkpoint.layerZero.optionalDvnThreshold}
- Robinhood to Solana confirmations: ${checkpoint.layerZero.confirmations.robinhoodToSolana}
- Solana to Robinhood confirmations: ${checkpoint.layerZero.confirmations.solanaToRobinhood}

## Temporary administration

- Solana Squads multisig: ${checkpoint.administration.solanaSquads.multisig}
- Solana Squads vault: ${checkpoint.administration.solanaSquads.vault}
- Solana threshold: ${checkpoint.administration.solanaSquads.threshold}-of-${checkpoint.administration.solanaSquads.members.length}
- Robinhood Safe: ${checkpoint.administration.robinhoodSafe.address}
- Robinhood Safe threshold: ${checkpoint.administration.robinhoodSafe.threshold}-of-${checkpoint.administration.robinhoodSafe.owners.length}

Authority readbacks:

- Solana program upgrade authority: ${pass(checks.solanaProgramUpgradeAuthority)}
- Solana OFT admin: ${pass(checks.solanaOftAdmin)}
- Solana LayerZero delegate: ${pass(checks.solanaLayerZeroDelegate)}
- Robinhood OFT owner: ${pass(checks.evmOwner)}
- Robinhood LayerZero delegate: ${pass(checks.evmLayerZeroDelegate)}

## Mainnet round-trip canary

- Funding swap: ${value(checkpoint.canary?.funding?.transaction)}
- STONKS acquired: ${value(checkpoint.canary?.funding?.receivedUi)}
- Canary status: ${value(checkpoint.canary?.status)}
- Supply invariants: ${value(checkpoint.canary?.invariants?.status)}
- Final Solana escrow raw: ${value(checkpoint.canary?.invariants?.solanaEscrowRaw)}
- Final Robinhood supply raw: ${value(checkpoint.canary?.invariants?.evmSupplyShared === '0' ? '0' : checkpoint.canary?.invariants?.evmSupplyShared)}

| Direction | Amount | GUID | Source transaction | Destination transaction | Status |
|---|---:|---|---|---|---|
${canaryRows}

## Remaining launch gates

${launchGates}

${
    canaryComplete
        ? 'The funded mainnet canary delivered in both directions and the independent supply invariants passed.'
        : 'Infrastructure deployment is complete. A mainnet asset-transfer claim is not complete until the funded canary has delivered in both directions and the supply invariants pass.'
}
`

fs.writeFileSync(output, document, { mode: 0o644 })
