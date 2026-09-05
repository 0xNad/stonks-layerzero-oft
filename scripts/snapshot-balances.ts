import fs from 'fs'
import path from 'path'

import { TOKEN_PROGRAM_ID, getAccount, getAssociatedTokenAddressSync, getMint } from '@solana/spl-token'
import { Connection, PublicKey } from '@solana/web3.js'
import { ethers } from 'ethers'

const root = path.resolve(__dirname, '..')
const checkpoint = JSON.parse(
    fs.readFileSync(
        process.env.CHECKPOINT_FILE ||
            path.join(root, 'deployments', process.env.DEPLOYMENT_ENV === 'mainnet' ? 'mainnet.json' : 'testnet.json'),
        'utf8'
    )
)
const isMainnet = process.env.DEPLOYMENT_ENV === 'mainnet'
const solanaRpc = isMainnet
    ? process.env.RPC_URL_SOLANA_MAINNET || process.env.RPC_URL_SOLANA || 'https://api.mainnet-beta.solana.com'
    : process.env.RPC_URL_SOLANA_TESTNET || process.env.RPC_URL_SOLANA || 'https://api.devnet.solana.com'
const evmRpc = isMainnet
    ? process.env.RPC_URL_ROBINHOOD_MAINNET || 'https://rpc.mainnet.chain.robinhood.com'
    : process.env.RPC_URL_ROBINHOOD_TESTNET || 'https://rpc.testnet.chain.robinhood.com'

async function main(): Promise<void> {
    const solana = new Connection(solanaRpc, 'confirmed')
    const evm = new ethers.providers.JsonRpcProvider(evmRpc, checkpoint.networks.evm.chainId)
    const mintPk = new PublicKey(checkpoint.token.mint)
    const userAtaPk = checkpoint.token.deployerAta
        ? new PublicKey(checkpoint.token.deployerAta)
        : getAssociatedTokenAddressSync(mintPk, new PublicKey(checkpoint.wallets.solana), false, TOKEN_PROGRAM_ID)
    const escrowPk = new PublicKey(checkpoint.solanaAdapter.escrow)
    const [mint, userAta, escrow, solanaGas] = await Promise.all([
        getMint(solana, mintPk, 'confirmed', TOKEN_PROGRAM_ID),
        getAccount(solana, userAtaPk, 'confirmed', TOKEN_PROGRAM_ID),
        getAccount(solana, escrowPk, 'confirmed', TOKEN_PROGRAM_ID),
        solana.getBalance(new PublicKey(checkpoint.wallets.solana), 'confirmed'),
    ])
    const oft = new ethers.Contract(
        checkpoint.evmOft.address,
        ['function totalSupply() view returns (uint256)', 'function balanceOf(address) view returns (uint256)'],
        evm
    )
    const [evmSupply, evmUser, evmGas] = await Promise.all([
        oft.totalSupply(),
        oft.balanceOf(checkpoint.wallets.evm),
        evm.getBalance(checkpoint.wallets.evm),
    ])
    console.log(
        JSON.stringify({
            capturedAt: new Date().toISOString(),
            solana: {
                userTokenRaw: userAta.amount.toString(),
                escrowRaw: escrow.amount.toString(),
                mintSupplyRaw: mint.supply.toString(),
                walletLamports: solanaGas.toString(),
            },
            evm: {
                userTokenRaw: evmUser.toString(),
                totalSupplyRaw: evmSupply.toString(),
                walletWei: evmGas.toString(),
            },
        })
    )
}

main().catch((error) => {
    console.error(error instanceof Error ? error.message : error)
    process.exit(1)
})
