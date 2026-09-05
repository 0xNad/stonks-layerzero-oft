import fs from 'fs'
import path from 'path'

import { Connection, PublicKey } from '@solana/web3.js'
import { ethers } from 'ethers'

import { defaultFetchMetadata } from '@layerzerolabs/metadata-tools'

const root = path.resolve(__dirname, '..')
const environment = process.env.DEPLOYMENT_ENV === 'mainnet' ? 'mainnet' : 'testnet'
const isMainnet = environment === 'mainnet'
const solanaEid = isMainnet ? 30168 : 40168
const robinhoodEid = isMainnet ? 30416 : 40451
const solanaRpc = isMainnet
    ? process.env.RPC_URL_SOLANA_MAINNET || 'https://api.mainnet-beta.solana.com'
    : process.env.RPC_URL_SOLANA_TESTNET || 'https://api.devnet.solana.com'
const robinhoodRpc = isMainnet
    ? process.env.RPC_URL_ROBINHOOD_MAINNET || 'https://rpc.mainnet.chain.robinhood.com'
    : process.env.RPC_URL_ROBINHOOD_TESTNET || 'https://rpc.testnet.chain.robinhood.com'
const expectedChainId = isMainnet ? 4663 : 46630
const expectedGenesis = isMainnet
    ? '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d'
    : 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG'
const requiredDvnNames = isMainnet ? ['LayerZero Labs'] : ['LayerZero Labs', 'Paxos']
const optionalDvnNames = isMainnet ? ['Nethermind', 'Horizen'] : []
const optionalDvnThreshold = isMainnet ? 1 : 0

type Json = Record<string, any>

function atomicWrite(file: string, value: Json): void {
    const tmp = `${file}.tmp`
    fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o644 })
    fs.renameSync(tmp, file)
}

function findMetadataEntry(metadata: Json, eid: number): { key: string; entry: Json; deployment: Json } {
    for (const [key, entry] of Object.entries(metadata)) {
        const deployment = (entry as Json).deployments?.find((item: Json) => Number(item.eid) === eid)
        if (deployment) return { key, entry: entry as Json, deployment }
    }
    throw new Error(`LayerZero metadata is missing EID ${eid}`)
}

function resolveDvns(entry: Json, names: string[]): Json[] {
    return names.map((name) => {
        const found = Object.entries(entry.dvns || {}).find(
            ([, value]) =>
                (value as Json).canonicalName === name &&
                Number((value as Json).version) === 2 &&
                !(value as Json).deprecated &&
                !(value as Json).lzReadCompatible
        )
        if (!found) throw new Error(`DVN ${name} is unavailable on ${entry.chainKey}`)
        return { name, address: found[0] }
    })
}

async function main(): Promise<void> {
    const metadata = (await defaultFetchMetadata()) as Json
    const solanaMetadata = findMetadataEntry(metadata, solanaEid)
    const robinhoodMetadata = findMetadataEntry(metadata, robinhoodEid)
    const solanaRequiredDvns = resolveDvns(solanaMetadata.entry, requiredDvnNames)
    const robinhoodRequiredDvns = resolveDvns(robinhoodMetadata.entry, requiredDvnNames)
    const solanaOptionalDvns = resolveDvns(solanaMetadata.entry, optionalDvnNames)
    const robinhoodOptionalDvns = resolveDvns(robinhoodMetadata.entry, optionalDvnNames)

    const evm = new ethers.providers.JsonRpcProvider(robinhoodRpc)
    const solana = new Connection(solanaRpc, 'confirmed')
    const [evmNetwork, solanaGenesis] = await Promise.all([evm.getNetwork(), solana.getGenesisHash()])
    if (evmNetwork.chainId !== expectedChainId) throw new Error(`Wrong Robinhood chain ${evmNetwork.chainId}`)
    if (solanaGenesis !== expectedGenesis) throw new Error(`Wrong Solana genesis ${solanaGenesis}`)

    const evmProtocolAddresses = {
        endpointV2: robinhoodMetadata.deployment.endpointV2?.address,
        sendUln302: robinhoodMetadata.deployment.sendUln302?.address,
        receiveUln302: robinhoodMetadata.deployment.receiveUln302?.address,
        executor: robinhoodMetadata.deployment.executor?.address,
    }
    for (const [label, address] of Object.entries(evmProtocolAddresses)) {
        if (!address || (await evm.getCode(address)) === '0x') throw new Error(`${label} has no bytecode at ${address}`)
    }
    for (const dvn of [...robinhoodRequiredDvns, ...robinhoodOptionalDvns]) {
        if ((await evm.getCode(dvn.address)) === '0x') throw new Error(`Robinhood DVN ${dvn.name} has no bytecode`)
    }

    const endpoint = new ethers.Contract(
        evmProtocolAddresses.endpointV2,
        ['function eid() view returns (uint32)', 'function isSupportedEid(uint32) view returns (bool)'],
        evm
    )
    const [reportedEid, supportsRemote] = await Promise.all([endpoint.eid(), endpoint.isSupportedEid(solanaEid)])
    if (Number(reportedEid.toString()) !== robinhoodEid || !supportsRemote) {
        throw new Error('Robinhood EndpointV2 EID or remote-EID support mismatch')
    }

    const solanaPrograms = {
        endpointV2: solanaMetadata.deployment.endpointV2?.address,
        sendUln302: solanaMetadata.deployment.sendUln302?.address,
        receiveUln302: solanaMetadata.deployment.receiveUln302?.address,
        executor: solanaMetadata.deployment.executor?.address,
        dvnProgram: solanaMetadata.deployment.dvn?.address,
    }
    const programEntries = Object.entries(solanaPrograms)
    const programAccounts = await solana.getMultipleAccountsInfo(
        programEntries.map(([, address]) => new PublicKey(address)),
        'confirmed'
    )
    programAccounts.forEach((account, index) => {
        if (!account?.executable) throw new Error(`Solana ${programEntries[index][0]} is missing or not executable`)
    })
    const solanaDvnAccounts = await solana.getMultipleAccountsInfo(
        [...solanaRequiredDvns, ...solanaOptionalDvns].map((dvn) => new PublicKey(dvn.address)),
        'confirmed'
    )
    solanaDvnAccounts.forEach((account, index) => {
        if (!account) {
            const dvn = [...solanaRequiredDvns, ...solanaOptionalDvns][index]
            throw new Error(`Solana DVN ${dvn.name} account is missing`)
        }
    })

    const result = {
        schemaVersion: 1,
        status: 'PASS',
        checkedAt: new Date().toISOString(),
        metadataUrl: 'https://metadata.layerzero-api.com/v1/metadata',
        environment,
        pathway: {
            solanaEid,
            robinhoodEid,
            confirmations: { robinhoodToSolana: 15, solanaToRobinhood: 32 },
            requiredDvns: requiredDvnNames,
            optionalDvns: optionalDvnNames,
            optionalDvnThreshold,
        },
        robinhood: {
            chainId: evmNetwork.chainId,
            metadataKey: robinhoodMetadata.key,
            protocol: evmProtocolAddresses,
            requiredDvns: robinhoodRequiredDvns,
            optionalDvns: robinhoodOptionalDvns,
            endpointReportedEid: Number(reportedEid.toString()),
            endpointSupportsSolanaEid: supportsRemote,
        },
        solana: {
            genesisHash: solanaGenesis,
            metadataKey: solanaMetadata.key,
            protocol: solanaPrograms,
            requiredDvns: solanaRequiredDvns,
            optionalDvns: solanaOptionalDvns,
        },
    }
    const output = path.join(root, 'deployments', `${environment}-readiness.json`)
    atomicWrite(output, result)
    console.log(JSON.stringify(result, null, 2))
}

main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exit(1)
})
