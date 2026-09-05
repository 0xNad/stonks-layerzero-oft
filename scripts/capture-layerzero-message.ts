import fs from 'fs'
import path from 'path'

const root = path.resolve(__dirname, '..')
const isMainnet = process.env.DEPLOYMENT_ENV === 'mainnet'
const checkpointPath =
    process.env.CHECKPOINT_FILE || path.join(root, 'deployments', isMainnet ? 'mainnet.json' : 'testnet.json')
const api = isMainnet ? 'https://scan.layerzero-api.com/v1' : 'https://scan-testnet.layerzero-api.com/v1'

const args = new Map<string, string>()
for (let i = 2; i < process.argv.length; i += 2) args.set(process.argv[i], process.argv[i + 1])
const sourceTxArg = args.get('--tx')
if (!sourceTxArg) throw new Error('--tx is required')
const sourceTx: string = sourceTxArg
const attempts = Number(process.env.LZ_POLL_ATTEMPTS || 120)
const delayMs = Number(process.env.LZ_POLL_INTERVAL_MS || 10000)

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
}

function writeJsonAtomic(file: string, value: any): void {
    const tmp = `${file}.tmp`
    fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o644 })
    fs.renameSync(tmp, file)
}

async function fetchMessage(): Promise<any | undefined> {
    const response = await fetch(`${api}/messages/tx/${encodeURIComponent(sourceTx)}`, {
        headers: { accept: 'application/json' },
    })
    if (response.status === 404) return undefined
    if (!response.ok) throw new Error(`LayerZero Scan HTTP ${response.status}: ${await response.text()}`)
    const body = (await response.json()) as any
    return body.data?.[0]
}

async function main(): Promise<void> {
    let message: any
    for (let attempt = 1; attempt <= attempts; attempt += 1) {
        try {
            message = await fetchMessage()
        } catch (error) {
            if (attempt === attempts) throw error
        }
        if (message) {
            console.error(
                `LayerZero ${message.guid}: ${message.status?.name}; source=${message.source?.status}; destination=${message.destination?.status}`
            )
            if (['FAILED', 'BLOCKED', 'PAYLOAD_STORED', 'APPLICATION_BURNED'].includes(message.status?.name)) {
                throw new Error(`LayerZero message entered terminal non-success status ${message.status.name}`)
            }
            if (message.status?.name === 'DELIVERED' && message.destination?.status === 'SUCCEEDED') break
        }
        if (attempt === attempts) throw new Error(`LayerZero delivery timed out after ${attempts} polls`)
        await sleep(delayMs)
    }

    const checkpoint = JSON.parse(fs.readFileSync(checkpointPath, 'utf8'))
    const messages = isMainnet ? checkpoint.canary.messages : checkpoint.messages
    const index = messages.findIndex((entry: any) => entry.sourceTransaction?.toLowerCase() === sourceTx.toLowerCase())
    if (index < 0) throw new Error(`Source transaction ${sourceTx} is not checkpointed`)
    messages[index] = {
        ...messages[index],
        guid: message.guid,
        status: message.status.name,
        sourceTransaction: message.source.tx.txHash,
        sourceBlock: message.source.tx.blockNumber,
        destinationTransaction: message.destination.tx.txHash,
        destinationBlock: message.destination.tx.blockNumber,
        deliveredAt: message.updated,
        pathway: message.pathway,
        deliveryConfig: message.config,
        scanApi: `${api}/messages/tx/${sourceTx}`,
    }
    checkpoint.updatedAt = new Date().toISOString()
    writeJsonAtomic(checkpointPath, checkpoint)
    console.log(JSON.stringify(messages[index], null, 2))
}

main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exit(1)
})
