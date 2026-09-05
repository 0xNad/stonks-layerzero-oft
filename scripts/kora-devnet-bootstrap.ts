import fs from 'fs'
import path from 'path'

import { Connection, Keypair, PublicKey, SystemInstruction, SystemProgram, Transaction } from '@solana/web3.js'

const root = path.resolve(__dirname, '..')
const checkpointPath = process.env.CHECKPOINT_FILE || path.join(root, 'deployments', 'testnet.json')
const rpcUrl = process.env.RPC_URL_SOLANA_TESTNET || process.env.RPC_URL_SOLANA || 'https://api.devnet.solana.com'
const koraUrl = process.env.KORA_DEVNET_URL || 'https://kora.devnet.lazorkit.com'
const devnetGenesis = 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG'
const systemProgram = SystemProgram.programId.toBase58()

type Json = Record<string, any>

async function koraRpc<T>(method: string, params?: Json): Promise<T> {
    const response = await fetch(koraUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
    })
    if (!response.ok) throw new Error(`Kora ${method} returned HTTP ${response.status}`)
    const payload = (await response.json()) as { result?: T; error?: { code: number; message: string } }
    if (payload.error) throw new Error(`Kora ${method} failed (${payload.error.code}): ${payload.error.message}`)
    if (payload.result === undefined) throw new Error(`Kora ${method} returned no result`)
    return payload.result
}

function writeCheckpoint(checkpoint: Json): void {
    checkpoint.updatedAt = new Date().toISOString()
    const tmp = `${checkpointPath}.tmp`
    fs.writeFileSync(tmp, `${JSON.stringify(checkpoint, null, 2)}\n`, { mode: 0o644 })
    fs.renameSync(tmp, checkpointPath)
}

async function main(): Promise<void> {
    const checkpoint = JSON.parse(fs.readFileSync(checkpointPath, 'utf8')) as Json
    const destination = new PublicKey(checkpoint.wallets.solana)
    const connection = new Connection(rpcUrl, 'confirmed')
    const genesis = await connection.getGenesisHash()
    if (genesis !== devnetGenesis) throw new Error(`Refusing write: RPC is not Solana Devnet (${genesis})`)

    const rentFloor = await connection.getMinimumBalanceForRentExemption(0, 'confirmed')
    const extraSigner = Keypair.generate().publicKey
    const { blockhash } = await connection.getLatestBlockhash('confirmed')
    const feeProbe = new Transaction({ feePayer: destination, recentBlockhash: blockhash }).add(
        SystemProgram.transfer({ fromPubkey: extraSigner, toPubkey: destination, lamports: 0 })
    )
    const fee = (await connection.getFeeForMessage(feeProbe.compileMessage(), 'confirmed')).value
    if (fee === null) throw new Error('Unable to quote the two-signature PoW transaction fee')
    const requiredBalance = rentFloor + fee
    const before = await connection.getBalance(destination, 'confirmed')
    if (before >= requiredBalance) {
        console.log(JSON.stringify({ status: 'ALREADY_FUNDED', before, requiredBalance, rentFloor, fee }))
        return
    }

    const config = await koraRpc<Json>('getConfig')
    const payer = new PublicKey(config.fee_payers?.[0])
    const gap = requiredBalance - before
    if (config.validation_config?.price?.type !== 'free') throw new Error('Kora Devnet paymaster is not free')
    if (!config.enabled_methods?.transfer_transaction || !config.enabled_methods?.sign_and_send_transaction) {
        throw new Error('Kora Devnet transfer/sign-and-send methods are unavailable')
    }
    if (!config.validation_config?.allowed_programs?.includes(systemProgram)) {
        throw new Error('Kora Devnet does not allow the System Program')
    }
    if (config.validation_config?.fee_payer_policy?.system?.allow_transfer !== true) {
        throw new Error('Kora Devnet does not permit fee-payer System transfers')
    }
    if (gap > Number(config.validation_config?.max_allowed_lamports || 0)) {
        throw new Error(`Required bootstrap gap ${gap} exceeds Kora's configured cap`)
    }

    const transfer = await koraRpc<Json>('transferTransaction', {
        amount: gap,
        token: systemProgram,
        source: payer.toBase58(),
        destination: destination.toBase58(),
        signer_key: payer.toBase58(),
    })
    const transaction = Transaction.from(Buffer.from(transfer.transaction, 'base64'))
    if (!transaction.feePayer?.equals(payer)) throw new Error('Kora transfer has an unexpected fee payer')
    if (transaction.instructions.length !== 1) throw new Error('Kora transfer has unexpected extra instructions')
    const decoded = SystemInstruction.decodeTransfer(transaction.instructions[0])
    if (
        !decoded.fromPubkey.equals(payer) ||
        !decoded.toPubkey.equals(destination) ||
        BigInt(decoded.lamports) !== BigInt(gap)
    ) {
        throw new Error('Kora transfer payload does not match the exact bootstrap gap')
    }

    const sent = await koraRpc<Json>('signAndSendTransaction', {
        transaction: transfer.transaction,
        signer_key: payer.toBase58(),
        sig_verify: false,
        respond_after: 'confirmed',
    })
    const status = await connection.getSignatureStatus(sent.signature, { searchTransactionHistory: true })
    if (status.value?.err) throw new Error(`Kora bootstrap transaction failed: ${JSON.stringify(status.value.err)}`)
    const after = await connection.getBalance(destination, 'confirmed')
    if (after < requiredBalance) throw new Error(`Bootstrap left ${after}; required ${requiredBalance}`)

    checkpoint.funding.solana = checkpoint.funding.solana || []
    if (!checkpoint.funding.solana.some((entry: Json) => entry.transactionSignature === sent.signature)) {
        checkpoint.funding.solana.push({
            source: 'LazorKit public Kora Devnet paymaster minimum PoW bootstrap',
            transactionSignature: sent.signature,
            amountLamports: gap.toString(),
            status: status.value?.confirmationStatus || 'confirmed',
        })
        writeCheckpoint(checkpoint)
    }
    console.log(
        JSON.stringify({
            status: 'PASS',
            signature: sent.signature,
            before,
            after,
            amountLamports: gap,
            requiredBalance,
            rentFloor,
            twoSignatureFee: fee,
        })
    )
}

main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exit(1)
})
