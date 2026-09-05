import fs from 'fs'
import path from 'path'

import { TOKEN_PROGRAM_ID, getAccount, getAssociatedTokenAddressSync, getMint } from '@solana/spl-token'
import { Connection, PublicKey } from '@solana/web3.js'
import { ethers } from 'ethers'

import { expectedEvmOwner } from './lib/invariant-policy'

const root = path.resolve(__dirname, '..')
const isMainnet = process.env.DEPLOYMENT_ENV === 'mainnet'
const checkpointPath =
    process.env.CHECKPOINT_FILE || path.join(root, 'deployments', isMainnet ? 'mainnet.json' : 'testnet.json')
const resultPath = path.join(root, 'deployments', isMainnet ? 'mainnet-invariant-result.json' : 'invariant-result.json')
const solanaRpc = isMainnet
    ? process.env.RPC_URL_SOLANA_MAINNET || process.env.RPC_URL_SOLANA || 'https://api.mainnet-beta.solana.com'
    : process.env.RPC_URL_SOLANA_TESTNET || process.env.RPC_URL_SOLANA || 'https://api.devnet.solana.com'
const evmRpc = isMainnet
    ? process.env.RPC_URL_ROBINHOOD_MAINNET || 'https://rpc.mainnet.chain.robinhood.com'
    : process.env.RPC_URL_ROBINHOOD_TESTNET || 'https://rpc.testnet.chain.robinhood.com'

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
    const userAtaAddress = checkpoint.token.deployerAta
        ? String(checkpoint.token.deployerAta)
        : getAssociatedTokenAddressSync(
              new PublicKey(mintAddress),
              new PublicKey(checkpoint.wallets.solana),
              false,
              TOKEN_PROGRAM_ID
          ).toBase58()
    const escrowAddress = requireValue<string>(checkpoint.solanaAdapter.escrow, 'solanaAdapter.escrow')
    const oftStoreAddress = requireValue<string>(checkpoint.solanaAdapter.oftStore, 'solanaAdapter.oftStore')
    const evmOftAddress = requireValue<string>(checkpoint.evmOft.address, 'evmOft.address')
    const fixedSupply = BigInt(
        requireValue<string>(
            checkpoint.token.fixedSupplyRaw || checkpoint.token.supplyRawBeforeBridge,
            'token fixed supply'
        )
    )
    const supplyBefore = BigInt(
        requireValue<string>(
            checkpoint.token.supplyBeforeBridgeRaw || checkpoint.token.supplyRawBeforeBridge,
            'token supply before bridge'
        )
    )

    const solana = new Connection(solanaRpc, 'confirmed')
    const genesis = await solana.getGenesisHash()
    const expectedGenesis = checkpoint.networks.solana.genesisHash || '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d'
    if (genesis !== expectedGenesis) throw new Error(`Wrong Solana cluster: ${genesis}`)

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

    const sharedChecks: Record<string, boolean> = {
        mintAuthorityRevoked: mint.mintAuthority === null,
        freezeAuthorityRevoked: mint.freezeAuthority === null,
        solanaSupplyUnchanged: mint.supply === supplyBefore && mint.supply === fixedSupply,
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
    let checks: Record<string, boolean>
    if (isMainnet) {
        const messages = checkpoint.canary?.messages || []
        const solanaToEvm = messages.find(
            (message: Json) => message.direction === 'SOLANA_TO_EVM' && message.status === 'DELIVERED'
        )
        const evmToSolana = [...messages]
            .reverse()
            .find((message: Json) => message.direction === 'EVM_TO_SOLANA' && message.status === 'DELIVERED')
        const initial = requireValue<Json>(solanaToEvm?.before, 'mainnet Solana-to-EVM before snapshot')
        const intermediate = requireValue<Json>(solanaToEvm?.after, 'mainnet Solana-to-EVM after snapshot')
        const final = requireValue<Json>(evmToSolana?.after, 'mainnet EVM-to-Solana after snapshot')
        const solanaAmount = BigInt(requireValue<string>(solanaToEvm?.amountLocalRaw, 'Solana canary amount'))
        const evmAmount = BigInt(requireValue<string>(evmToSolana?.amountLocalRaw, 'EVM canary amount'))

        checks = {
            ...sharedChecks,
            canonicalStonksMint: mintAddress === 'stonksUpymwbn1rBBpZmd1u92ydJ2asGw1y7capGMzW',
            messagesDeliveredBidirectionally: Boolean(solanaToEvm && evmToSolana),
            sharedAmountsMatch: solanaToEvm.amountSharedRaw === evmToSolana.amountSharedRaw,
            solanaLockDeltaCorrect:
                BigInt(initial.solana.userTokenRaw) - BigInt(intermediate.solana.userTokenRaw) === solanaAmount &&
                BigInt(intermediate.solana.escrowRaw) - BigInt(initial.solana.escrowRaw) === solanaAmount,
            evmMintDeltaCorrect:
                BigInt(intermediate.evm.totalSupplyRaw) - BigInt(initial.evm.totalSupplyRaw) === evmAmount &&
                BigInt(intermediate.evm.userTokenRaw) - BigInt(initial.evm.userTokenRaw) === evmAmount,
            evmBurnDeltaCorrect:
                BigInt(intermediate.evm.totalSupplyRaw) - BigInt(final.evm.totalSupplyRaw) === evmAmount &&
                BigInt(intermediate.evm.userTokenRaw) - BigInt(final.evm.userTokenRaw) === evmAmount,
            solanaReleaseDeltaCorrect:
                BigInt(final.solana.userTokenRaw) - BigInt(intermediate.solana.userTokenRaw) === solanaAmount &&
                BigInt(intermediate.solana.escrowRaw) - BigInt(final.solana.escrowRaw) === solanaAmount,
            solanaUserRoundTripRestored: BigInt(final.solana.userTokenRaw) === BigInt(initial.solana.userTokenRaw),
            escrowRoundTripRestored: BigInt(final.solana.escrowRaw) === BigInt(initial.solana.escrowRaw),
            evmSupplyRoundTripRestored: BigInt(final.evm.totalSupplyRaw) === BigInt(initial.evm.totalSupplyRaw),
            evmUserRoundTripRestored: BigInt(final.evm.userTokenRaw) === BigInt(initial.evm.userTokenRaw),
        }
    } else {
        checks = {
            ...sharedChecks,
            circulatingPlusEscrowEqualsFixedSupply: userAta.amount + escrow.amount === fixedSupply,
        }
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
    const checkpointInvariants = {
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
    if (isMainnet) {
        checkpoint.canary.status = result.status
        checkpoint.canary.invariants = checkpointInvariants
    } else {
        checkpoint.invariants = checkpointInvariants
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
