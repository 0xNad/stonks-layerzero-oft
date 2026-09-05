import fs from 'fs'
import path from 'path'

import { ethers } from 'ethers'

const root = path.resolve(__dirname, '..')
const environment = process.env.DEPLOYMENT_ENV === 'mainnet' ? 'mainnet' : 'testnet'
const isMainnet = environment === 'mainnet'
const checkpointPath =
    process.env.CHECKPOINT_FILE || path.join(root, 'deployments', isMainnet ? 'mainnet.json' : 'testnet.json')
const deploymentPath = path.join(
    root,
    'deployments',
    isMainnet ? 'robinhood-mainnet' : 'robinhood-testnet',
    'StonksOFT.json'
)
const rpcUrl = isMainnet
    ? process.env.RPC_URL_ROBINHOOD_MAINNET || 'https://rpc.mainnet.chain.robinhood.com'
    : process.env.RPC_URL_ROBINHOOD_TESTNET || 'https://rpc.testnet.chain.robinhood.com'
const expectedChainId = isMainnet ? 4663 : 46630
const expectedName = isMainnet ? 'Stonks' : 'Test STONKS'
const expectedSymbol = isMainnet ? 'STONKS' : 'tSTONKS'

function writeJsonAtomic(file: string, value: any): void {
    const tmp = `${file}.tmp`
    fs.writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o644 })
    fs.renameSync(tmp, file)
}

async function main(): Promise<void> {
    const checkpoint = JSON.parse(fs.readFileSync(checkpointPath, 'utf8'))
    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'))
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl, expectedChainId)
    const network = await provider.getNetwork()
    if (network.chainId !== expectedChainId)
        throw new Error(`Refusing read/write checkpoint for chain ${network.chainId}`)

    const mintAbi = deployment.abi.find((entry: any) => entry.type === 'function' && entry.name === 'mint')
    if (mintAbi) throw new Error('Production ABI exposes a public mint function')

    const code = await provider.getCode(deployment.address)
    if (code === '0x') throw new Error('No bytecode at deployed OFT address')
    const contract = new ethers.Contract(deployment.address, deployment.abi, provider)
    const [name, symbol, decimalsRaw, supply, owner, endpoint] = await Promise.all([
        contract.name(),
        contract.symbol(),
        contract.decimals(),
        contract.totalSupply(),
        contract.owner(),
        contract.endpoint(),
    ])
    const decimals = Number(decimalsRaw.toString())
    if (name !== expectedName || symbol !== expectedSymbol || decimals !== 18) throw new Error('OFT metadata mismatch')
    const expectedOwners = [checkpoint.wallets.evm, checkpoint.administration?.robinhoodSafe?.address]
        .filter(Boolean)
        .map((value: string) => value.toLowerCase())
    if (!expectedOwners.includes(owner.toLowerCase()))
        throw new Error('OFT owner is neither bootstrap deployer nor protected Safe')
    if (endpoint.toLowerCase() !== checkpoint.evmOft.endpoint.toLowerCase()) throw new Error('OFT endpoint mismatch')

    checkpoint.updatedAt = new Date().toISOString()
    checkpoint.evmOft.address = deployment.address
    checkpoint.evmOft.deploymentTransaction = deployment.transactionHash || checkpoint.evmOft.deploymentTransaction
    checkpoint.evmOft.name = name
    checkpoint.evmOft.symbol = symbol
    checkpoint.evmOft.decimals = decimals
    checkpoint.evmOft.owner = owner
    checkpoint.evmOft.endpoint = endpoint
    if (!checkpoint.evmOft.addressPreviouslyObserved) {
        if (!supply.isZero()) throw new Error(`Newly deployed EVM OFT did not begin with zero supply: ${supply}`)
        checkpoint.evmOft.initialSupplyRaw = '0'
        checkpoint.evmOft.addressPreviouslyObserved = true
    }
    writeJsonAtomic(checkpointPath, checkpoint)

    console.log(
        JSON.stringify(
            {
                status: 'PASS',
                address: deployment.address,
                transactionHash: deployment.transactionHash,
                name,
                symbol,
                decimals,
                totalSupplyRaw: supply.toString(),
                owner,
                endpoint,
                publicMintFunction: false,
                bytecodeBytes: (code.length - 2) / 2,
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
