import fs from 'fs'
import path from 'path'

import Safe from '@safe-global/protocol-kit'
import {
    getCompatibilityFallbackHandlerDeployment,
    getMultiSendCallOnlyDeployment,
    getMultiSendDeployment,
    getProxyFactoryDeployment,
    getSafeL2SingletonDeployment,
} from '@safe-global/safe-deployments'
import { Connection, Keypair } from '@solana/web3.js'
import * as multisig from '@sqds/multisig'
import { ethers } from 'ethers'

const root = path.resolve(__dirname, '..')
const environment = process.env.DEPLOYMENT_ENV === 'mainnet' ? 'mainnet' : 'testnet'
const isMainnet = environment === 'mainnet'
const checkpointPath =
    process.env.CHECKPOINT_FILE || path.join(root, 'deployments', isMainnet ? 'mainnet.json' : 'testnet.json')
const solanaKeypairPath =
    process.env.SOLANA_KEYPAIR_PATH ||
    path.join(root, isMainnet ? '.mainnet-secrets' : '.testnet-secrets', 'solana-deployer.json')
const squadsCreateKeyPath = path.join(
    root,
    isMainnet ? '.mainnet-secrets' : '.testnet-secrets',
    'squads-create-key.json'
)
const solanaRpc = isMainnet
    ? process.env.RPC_URL_SOLANA_MAINNET || 'https://api.mainnet-beta.solana.com'
    : process.env.RPC_URL_SOLANA_TESTNET || 'https://api.devnet.solana.com'
const evmRpc = isMainnet
    ? process.env.RPC_URL_ROBINHOOD_MAINNET || 'https://rpc.mainnet.chain.robinhood.com'
    : process.env.RPC_URL_ROBINHOOD_TESTNET || 'https://rpc.testnet.chain.robinhood.com'
const expectedEvmChainId = isMainnet ? 4663 : 46630
const expectedSolanaGenesis = isMainnet
    ? '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d'
    : 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG'
const safeVersion = '1.5.0'

type Json = Record<string, any>

function readKeypair(file: string): Keypair {
    return Keypair.fromSecretKey(Uint8Array.from(JSON.parse(fs.readFileSync(file, 'utf8')) as number[]))
}

function readCheckpoint(): Json {
    return JSON.parse(fs.readFileSync(checkpointPath, 'utf8')) as Json
}

function writeCheckpoint(checkpoint: Json): void {
    checkpoint.updatedAt = new Date().toISOString()
    const tmp = `${checkpointPath}.tmp`
    fs.writeFileSync(tmp, `${JSON.stringify(checkpoint, null, 2)}\n`, { mode: 0o644 })
    fs.renameSync(tmp, checkpointPath)
}

function deploymentAddress(deployment: any): string {
    const address = deployment?.networkAddresses?.[String(expectedEvmChainId)]
    if (!address) throw new Error(`Safe ${safeVersion} deployment is missing for chain ${expectedEvmChainId}`)
    return address
}

async function createOrVerifySquads(checkpoint: Json): Promise<void> {
    const connection = new Connection(solanaRpc, 'confirmed')
    const genesis = await connection.getGenesisHash()
    if (genesis !== expectedSolanaGenesis) throw new Error(`Refusing Solana write on unexpected genesis ${genesis}`)

    const creator = readKeypair(solanaKeypairPath)
    const createKey = readKeypair(squadsCreateKeyPath)
    if (creator.publicKey.toBase58() !== checkpoint.wallets.solana) {
        throw new Error('Solana deployer does not match checkpoint')
    }

    const [multisigPda] = multisig.getMultisigPda({ createKey: createKey.publicKey })
    const [vaultPda] = multisig.getVaultPda({ multisigPda, index: 0 })
    const protectedMultisig = checkpoint.administration.solanaSquads.multisig
    if (protectedMultisig && protectedMultisig !== multisigPda.toBase58()) {
        throw new Error(`Protected Squads address ${protectedMultisig} differs from derived ${multisigPda.toBase58()}`)
    }

    let createTransaction = checkpoint.administration.solanaSquads.createTransaction
    if (!(await connection.getAccountInfo(multisigPda, 'confirmed'))) {
        const [programConfigPda] = multisig.getProgramConfigPda({})
        const programConfig = await multisig.accounts.ProgramConfig.fromAccountAddress(
            connection,
            programConfigPda,
            'confirmed'
        )
        createTransaction = await multisig.rpc.multisigCreateV2({
            connection,
            treasury: programConfig.treasury,
            createKey,
            creator,
            multisigPda,
            configAuthority: null,
            threshold: 1,
            members: [{ key: creator.publicKey, permissions: multisig.types.Permissions.all() }],
            timeLock: 0,
            rentCollector: null,
            memo: `STONKS LayerZero ${environment} bootstrap admin`,
            sendOptions: { skipPreflight: false, preflightCommitment: 'confirmed', maxRetries: 5 },
        })
        await connection.confirmTransaction(createTransaction, 'confirmed')
    }

    const account = await multisig.accounts.Multisig.fromAccountAddress(connection, multisigPda, 'confirmed')
    const member = account.members.find((entry) => entry.key.equals(creator.publicKey))
    if (account.threshold !== 1 || account.members.length !== 1 || !member) {
        throw new Error('Squads account is not the intended temporary 1-of-1 configuration')
    }
    if (!multisig.types.Permissions.has(member.permissions, multisig.types.Permission.Initiate)) {
        throw new Error('Squads bootstrap owner lacks Initiate permission')
    }
    if (!multisig.types.Permissions.has(member.permissions, multisig.types.Permission.Vote)) {
        throw new Error('Squads bootstrap owner lacks Vote permission')
    }
    if (!multisig.types.Permissions.has(member.permissions, multisig.types.Permission.Execute)) {
        throw new Error('Squads bootstrap owner lacks Execute permission')
    }

    checkpoint.administration.solanaSquads.multisig = multisigPda.toBase58()
    checkpoint.administration.solanaSquads.vault = vaultPda.toBase58()
    checkpoint.administration.solanaSquads.createTransaction = createTransaction || null
    checkpoint.administration.solanaSquads.verifiedAt = new Date().toISOString()
    writeCheckpoint(checkpoint)
}

async function createOrVerifySafe(checkpoint: Json): Promise<void> {
    const privateKey = process.env.PRIVATE_KEY
    if (!privateKey || !/^0x[0-9a-fA-F]{64}$/.test(privateKey)) throw new Error('PRIVATE_KEY is missing or invalid')
    const provider = new ethers.providers.JsonRpcProvider(evmRpc)
    const network = await provider.getNetwork()
    if (network.chainId !== expectedEvmChainId) throw new Error(`Refusing EVM write on chain ${network.chainId}`)
    const wallet = new ethers.Wallet(privateKey, provider)
    if (wallet.address.toLowerCase() !== checkpoint.wallets.evm.toLowerCase()) {
        throw new Error('EVM deployer does not match checkpoint')
    }

    const singleton = getSafeL2SingletonDeployment({ version: safeVersion, network: String(expectedEvmChainId) })
    const factory = getProxyFactoryDeployment({ version: safeVersion, network: String(expectedEvmChainId) })
    const fallback = getCompatibilityFallbackHandlerDeployment({
        version: safeVersion,
        network: String(expectedEvmChainId),
    })
    const multiSend = getMultiSendDeployment({ version: safeVersion, network: String(expectedEvmChainId) })
    const multiSendCallOnly = getMultiSendCallOnlyDeployment({
        version: safeVersion,
        network: String(expectedEvmChainId),
    })
    for (const deployment of [singleton, factory, fallback, multiSend, multiSendCallOnly]) {
        const address = deploymentAddress(deployment)
        if ((await provider.getCode(address)) === '0x') throw new Error(`Safe dependency has no bytecode at ${address}`)
    }

    const contractNetworks = {
        [String(expectedEvmChainId)]: {
            safeSingletonAddress: deploymentAddress(singleton),
            safeSingletonAbi: singleton!.abi as any,
            safeProxyFactoryAddress: deploymentAddress(factory),
            safeProxyFactoryAbi: factory!.abi as any,
            fallbackHandlerAddress: deploymentAddress(fallback),
            fallbackHandlerAbi: fallback!.abi as any,
            multiSendAddress: deploymentAddress(multiSend),
            multiSendAbi: multiSend!.abi as any,
            multiSendCallOnlyAddress: deploymentAddress(multiSendCallOnly),
            multiSendCallOnlyAbi: multiSendCallOnly!.abi as any,
        },
    }
    const predicted = await Safe.init({
        provider: evmRpc,
        signer: privateKey,
        contractNetworks,
        predictedSafe: {
            safeAccountConfig: { owners: [wallet.address], threshold: 1 },
            safeDeploymentConfig: { safeVersion, saltNonce: String(expectedEvmChainId) },
        },
    })
    const safeAddress = await predicted.getAddress()
    const protectedSafe = checkpoint.administration.robinhoodSafe.address
    if (protectedSafe && protectedSafe.toLowerCase() !== safeAddress.toLowerCase()) {
        throw new Error(`Protected Safe ${protectedSafe} differs from predicted ${safeAddress}`)
    }

    let deploymentTransaction = checkpoint.administration.robinhoodSafe.deploymentTransaction
    if ((await provider.getCode(safeAddress)) === '0x') {
        const deployment = await predicted.createSafeDeploymentTransaction()
        const tx = await wallet.sendTransaction({ to: deployment.to, data: deployment.data, value: deployment.value })
        deploymentTransaction = tx.hash
        const receipt = await tx.wait(1)
        if (receipt.status !== 1) throw new Error('Safe deployment transaction reverted')
    }

    const deployed = await Safe.init({
        provider: evmRpc,
        signer: privateKey,
        safeAddress,
        contractNetworks,
    })
    const [owners, threshold, version] = await Promise.all([
        deployed.getOwners(),
        deployed.getThreshold(),
        deployed.getContractVersion(),
    ])
    if (
        owners.length !== 1 ||
        owners[0].toLowerCase() !== wallet.address.toLowerCase() ||
        threshold !== 1 ||
        version !== safeVersion
    ) {
        throw new Error('Safe is not the intended temporary 1-of-1 v1.5.0 configuration')
    }

    checkpoint.administration.robinhoodSafe.address = safeAddress
    checkpoint.administration.robinhoodSafe.deploymentTransaction = deploymentTransaction || null
    checkpoint.administration.robinhoodSafe.verifiedAt = new Date().toISOString()
    writeCheckpoint(checkpoint)
}

async function main(): Promise<void> {
    const checkpoint = readCheckpoint()
    await createOrVerifySquads(checkpoint)
    await createOrVerifySafe(checkpoint)
    console.log(
        JSON.stringify(
            {
                status: 'PASS',
                environment,
                solanaSquads: checkpoint.administration.solanaSquads,
                robinhoodSafe: checkpoint.administration.robinhoodSafe,
            },
            null,
            2
        )
    )
}

main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exit(1)
})
