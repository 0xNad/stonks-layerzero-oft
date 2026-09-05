import fs from 'fs'
import path from 'path'

import { TOKEN_PROGRAM_ID, getAccount, getMint } from '@solana/spl-token'
import { Connection, PublicKey } from '@solana/web3.js'
import { ethers } from 'ethers'

import { expectedEvmOwner } from './lib/invariant-policy'

const root = path.resolve(__dirname, '..')
const checkpointPath = process.env.CHECKPOINT_FILE || path.join(root, 'deployments', 'testnet.json')
const resultPath = path.join(root, 'deployments', 'invariant-result.json')
const solanaRpc = process.env.RPC_URL_SOLANA_TESTNET || process.env.RPC_URL_SOLANA || 'https://api.devnet.solana.com'
const evmRpc = process.env.RPC_URL_ROBINHOOD_TESTNET || 'https://rpc.testnet.chain.robinhood.com'

type Json = Record<string, any>

const abi = [
    'function totalSupply() view returns (uint256)',
    'function balanceOf(address) view returns (uint256)',
    'function decimals() view returns (uint8)',
    'function name() view returns (string)',
    'function symbol() view returns (string)',
    'function owner() view returns (address)',
    'function endpoint() view returns (address)',
]

function requireValue<T>(value: T | null | undefined, label: string): T {
    if (value === null || value === undefined || value === '') throw new Error(`Missing checkpoint value: ${label}`)
    return value
}

function clean(amount: bigint, conversionRate: bigint): bigint {
    return amount - (amount % conversionRate)
}

function writeJsonAtomic(file: string, value: Json): void {
    const tmp = `${file}.tmp`
    fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o644 })
    fs.renameSync(tmp, file)
}

async function main(): Promise<void> {
    const checkpoint = JSON.parse(fs.readFileSync(checkpointPath, 'utf8')) as Json
    const mintAddress = requireValue<string>(checkpoint.token.mint, 'token.mint')
    const userAtaAddress = requireValue<string>(checkpoint.token.deployerAta, 'token.deployerAta')
    const escrowAddress = requireValue<string>(checkpoint.solanaAdapter.escrow, 'solanaAdapter.escrow')
    const oftStoreAddress = requireValue<string>(checkpoint.solanaAdapter.oftStore, 'solanaAdapter.oftStore')
    const evmOftAddress = requireValue<string>(checkpoint.evmOft.address, 'evmOft.address')
    const fixedSupply = BigInt(requireValue<string>(checkpoint.token.fixedSupplyRaw, 'token.fixedSupplyRaw'))
    const supplyBefore = BigInt(
        requireValue<string>(checkpoint.token.supplyBeforeBridgeRaw, 'token.supplyBeforeBridgeRaw')
    )

    const solana = new Connection(solanaRpc, 'confirmed')
    const genesis = await solana.getGenesisHash()
    if (genesis !== checkpoint.networks.solana.genesisHash) throw new Error(`Wrong Solana cluster: ${genesis}`)

    const evm = new ethers.providers.JsonRpcProvider(evmRpc, checkpoint.networks.evm.chainId)
    const chain = await evm.getNetwork()
    if (chain.chainId !== checkpoint.networks.evm.chainId) throw new Error(`Wrong EVM chain: ${chain.chainId}`)

    const mint = await getMint(solana, new PublicKey(mintAddress), 'confirmed', TOKEN_PROGRAM_ID)
    const userAta = await getAccount(solana, new PublicKey(userAtaAddress), 'confirmed', TOKEN_PROGRAM_ID)
    const escrow = await getAccount(solana, new PublicKey(escrowAddress), 'confirmed', TOKEN_PROGRAM_ID)
    const oftStore = new PublicKey(oftStoreAddress)
    if (!escrow.owner.equals(oftStore)) throw new Error('Escrow token-account owner is not the OFT Store PDA')

    const code = await evm.getCode(evmOftAddress)
    if (code === '0x') throw new Error('EVM OFT has no deployed bytecode')
    const oft = new ethers.Contract(evmOftAddress, abi, evm)
    const [evmSupplyBn, evmUserBn, evmDecimals, name, symbol, owner, endpoint] = await Promise.all([
        oft.totalSupply(),
        oft.balanceOf(checkpoint.wallets.evm),
        oft.decimals(),
        oft.name(),
        oft.symbol(),
        oft.owner(),
        oft.endpoint(),
    ])
    const evmSupply = BigInt(evmSupplyBn.toString())
    const evmUser = BigInt(evmUserBn.toString())
    const evmDecimalsNumber = Number(evmDecimals.toString())

    const solanaConversion = 10n ** BigInt(checkpoint.token.decimals - checkpoint.token.sharedDecimals)
    const evmConversion = 10n ** BigInt(evmDecimalsNumber - checkpoint.token.sharedDecimals)
    const normalizedEscrow = escrow.amount / solanaConversion
    const normalizedEvmSupply = evmSupply / evmConversion

    const checks: Record<string, boolean> = {
        mintAuthorityRevoked: mint.mintAuthority === null,
        freezeAuthorityRevoked: mint.freezeAuthority === null,
        solanaSupplyUnchanged: mint.supply === supplyBefore && mint.supply === fixedSupply,
        circulatingPlusEscrowEqualsFixedSupply: userAta.amount + escrow.amount === fixedSupply,
        normalizedEscrowEqualsEvmSupply: normalizedEscrow === normalizedEvmSupply,
        solanaEscrowHasNoDust: escrow.amount % solanaConversion === 0n,
        evmSupplyHasNoDust: evmSupply % evmConversion === 0n,
        evmUserOwnsOutstandingSupply: evmUser === evmSupply,
        evmMetadataCorrect:
            name === checkpoint.evmOft.name && symbol === checkpoint.evmOft.symbol && evmDecimalsNumber === 18,
        evmOwnerCorrect: owner.toLowerCase() === expectedEvmOwner(checkpoint).toLowerCase(),
        evmEndpointCorrect: endpoint.toLowerCase() === checkpoint.evmOft.endpoint.toLowerCase(),
        solanaDustCleaning: clean(1_001n, solanaConversion) === 1_000n,
        evmDustCleaning: clean(1_000_000_000_001n, evmConversion) === 1_000_000_000_000n,
    }
    const passed = Object.values(checks).every(Boolean)
    const result = {
        status: passed ? 'PASS' : 'FAIL',
        checkedAt: new Date().toISOString(),
        checks,
        values: {
            solanaMintSupplyRaw: mint.supply.toString(),
            solanaSupplyBeforeRaw: supplyBefore.toString(),
            solanaUserRaw: userAta.amount.toString(),
            solanaEscrowRaw: escrow.amount.toString(),
            normalizedEscrowShared: normalizedEscrow.toString(),
            evmTotalSupplyRaw: evmSupply.toString(),
            evmUserRaw: evmUser.toString(),
            normalizedEvmSupplyShared: normalizedEvmSupply.toString(),
            solanaConversionRate: solanaConversion.toString(),
            evmConversionRate: evmConversion.toString(),
        },
    }

    checkpoint.updatedAt = result.checkedAt
    checkpoint.invariants = {
        status: result.status,
        normalizedEscrowShared: result.values.normalizedEscrowShared,
        evmSupplyShared: result.values.normalizedEvmSupplyShared,
        solanaSupplyBeforeRaw: result.values.solanaSupplyBeforeRaw,
        solanaSupplyAfterRaw: result.values.solanaMintSupplyRaw,
        solanaUserRaw: result.values.solanaUserRaw,
        solanaEscrowRaw: result.values.solanaEscrowRaw,
        checkedAt: result.checkedAt,
        checks,
    }
    writeJsonAtomic(resultPath, result)
    writeJsonAtomic(checkpointPath, checkpoint)
    console.log(JSON.stringify(result, null, 2))
    if (!passed) process.exit(1)
}

main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exit(1)
})
