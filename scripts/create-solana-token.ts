import fs from 'fs'
import path from 'path'

import {
    AuthorityType,
    MINT_SIZE,
    TOKEN_PROGRAM_ID,
    createAssociatedTokenAccountInstruction,
    createInitializeMintInstruction,
    createMintToInstruction,
    createSetAuthorityInstruction,
    getAccount,
    getAssociatedTokenAddressSync,
    getMint,
} from '@solana/spl-token'
import { Connection, Keypair, SystemProgram, Transaction, sendAndConfirmTransaction } from '@solana/web3.js'

const root = path.resolve(__dirname, '..')
const checkpointPath = process.env.CHECKPOINT_FILE || path.join(root, 'deployments', 'testnet.json')
const payerPath = process.env.SOLANA_KEYPAIR_PATH || path.join(root, '.testnet-secrets', 'solana-deployer.json')
const mintKeypairPath = path.join(root, '.testnet-secrets', 'tstonks-mint.json')
const rpcUrl = process.env.RPC_URL_SOLANA_TESTNET || process.env.RPC_URL_SOLANA || 'https://api.devnet.solana.com'

const decimals = 9
const fixedSupplyRaw = 1_000_000_000n * 10n ** BigInt(decimals)

type Json = Record<string, any>

function readKeypair(file: string): Keypair {
    const bytes = JSON.parse(fs.readFileSync(file, 'utf8')) as number[]
    return Keypair.fromSecretKey(Uint8Array.from(bytes))
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

function loadOrCreateMintKeypair(): Keypair {
    if (fs.existsSync(mintKeypairPath)) return readKeypair(mintKeypairPath)
    const mint = Keypair.generate()
    fs.writeFileSync(mintKeypairPath, JSON.stringify(Array.from(mint.secretKey)), { mode: 0o600 })
    fs.chmodSync(mintKeypairPath, 0o600)
    return mint
}

async function send(connection: Connection, transaction: Transaction, signers: Keypair[]): Promise<string> {
    return sendAndConfirmTransaction(connection, transaction, signers, {
        commitment: 'confirmed',
        preflightCommitment: 'confirmed',
        skipPreflight: false,
        maxRetries: 5,
    })
}

async function main(): Promise<void> {
    const connection = new Connection(rpcUrl, 'confirmed')
    const genesis = await connection.getGenesisHash()
    if (genesis !== 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG') {
        throw new Error(`Refusing write: RPC is not Solana Devnet (genesis ${genesis})`)
    }

    const payer = readKeypair(payerPath)
    const checkpoint = readCheckpoint()
    if (checkpoint.wallets.solana !== payer.publicKey.toBase58()) {
        throw new Error('Solana keypair does not match the public deployment checkpoint')
    }

    const mintKeypair = loadOrCreateMintKeypair()
    const mintAddress = mintKeypair.publicKey.toBase58()
    if (checkpoint.token.mint && checkpoint.token.mint !== mintAddress) {
        throw new Error(`Checkpoint mint ${checkpoint.token.mint} does not match protected mint keypair ${mintAddress}`)
    }
    checkpoint.token.mint = mintAddress
    writeCheckpoint(checkpoint)

    const existingMint = await connection.getAccountInfo(mintKeypair.publicKey, 'confirmed')
    if (!existingMint) {
        const lamports = await connection.getMinimumBalanceForRentExemption(MINT_SIZE)
        const tx = new Transaction().add(
            SystemProgram.createAccount({
                fromPubkey: payer.publicKey,
                newAccountPubkey: mintKeypair.publicKey,
                lamports,
                space: MINT_SIZE,
                programId: TOKEN_PROGRAM_ID,
            }),
            createInitializeMintInstruction(
                mintKeypair.publicKey,
                decimals,
                payer.publicKey,
                payer.publicKey,
                TOKEN_PROGRAM_ID
            )
        )
        checkpoint.token.transactions.createMint = await send(connection, tx, [payer, mintKeypair])
        writeCheckpoint(checkpoint)
    }

    const ata = getAssociatedTokenAddressSync(mintKeypair.publicKey, payer.publicKey, false, TOKEN_PROGRAM_ID)
    checkpoint.token.deployerAta = ata.toBase58()
    const existingAta = await connection.getAccountInfo(ata, 'confirmed')
    if (!existingAta) {
        const tx = new Transaction().add(
            createAssociatedTokenAccountInstruction(
                payer.publicKey,
                ata,
                payer.publicKey,
                mintKeypair.publicKey,
                TOKEN_PROGRAM_ID
            )
        )
        checkpoint.token.transactions.createAta = await send(connection, tx, [payer])
        writeCheckpoint(checkpoint)
    }

    let mintState = await getMint(connection, mintKeypair.publicKey, 'confirmed', TOKEN_PROGRAM_ID)
    if (mintState.supply === 0n) {
        const tx = new Transaction().add(
            createMintToInstruction(mintKeypair.publicKey, ata, payer.publicKey, fixedSupplyRaw, [], TOKEN_PROGRAM_ID)
        )
        checkpoint.token.transactions.mintSupply = await send(connection, tx, [payer])
        writeCheckpoint(checkpoint)
        mintState = await getMint(connection, mintKeypair.publicKey, 'confirmed', TOKEN_PROGRAM_ID)
    }
    if (mintState.supply !== fixedSupplyRaw) {
        throw new Error(`Unexpected tSTONKS supply ${mintState.supply}; expected ${fixedSupplyRaw}`)
    }

    const revoke = new Transaction()
    if (mintState.mintAuthority) {
        if (!mintState.mintAuthority.equals(payer.publicKey)) throw new Error('Unexpected mint authority')
        revoke.add(
            createSetAuthorityInstruction(
                mintKeypair.publicKey,
                payer.publicKey,
                AuthorityType.MintTokens,
                null,
                [],
                TOKEN_PROGRAM_ID
            )
        )
    }
    if (mintState.freezeAuthority) {
        if (!mintState.freezeAuthority.equals(payer.publicKey)) throw new Error('Unexpected freeze authority')
        revoke.add(
            createSetAuthorityInstruction(
                mintKeypair.publicKey,
                payer.publicKey,
                AuthorityType.FreezeAccount,
                null,
                [],
                TOKEN_PROGRAM_ID
            )
        )
    }
    if (revoke.instructions.length > 0) {
        checkpoint.token.transactions.revokeAuthorities = await send(connection, revoke, [payer])
        writeCheckpoint(checkpoint)
    }

    mintState = await getMint(connection, mintKeypair.publicKey, 'confirmed', TOKEN_PROGRAM_ID)
    const userAccount = await getAccount(connection, ata, 'confirmed', TOKEN_PROGRAM_ID)
    if (mintState.mintAuthority !== null || mintState.freezeAuthority !== null) {
        throw new Error('Token authorities were not fully revoked')
    }
    if (mintState.supply !== fixedSupplyRaw || userAccount.amount !== fixedSupplyRaw) {
        throw new Error('Fixed supply or deployer balance verification failed')
    }

    checkpoint.token.mintAuthority = null
    checkpoint.token.freezeAuthority = null
    checkpoint.token.supplyBeforeBridgeRaw = mintState.supply.toString()
    checkpoint.externalBlockers = (checkpoint.externalBlockers as string[]).filter(
        (item) => !item.includes('initial 5000-lamport seed')
    )
    writeCheckpoint(checkpoint)

    console.log(
        JSON.stringify(
            {
                status: 'PASS',
                mint: mintAddress,
                deployerAta: ata.toBase58(),
                decimals,
                fixedSupplyRaw: mintState.supply.toString(),
                mintAuthority: null,
                freezeAuthority: null,
                transactions: checkpoint.token.transactions,
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
