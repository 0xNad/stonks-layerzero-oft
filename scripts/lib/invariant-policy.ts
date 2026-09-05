type Checkpoint = {
    wallets?: { evm?: string }
    evmOft?: { owner?: string }
}

export function expectedEvmOwner(checkpoint: Checkpoint): string {
    const owner = checkpoint.evmOft?.owner || checkpoint.wallets?.evm
    if (!owner) throw new Error('Missing checkpoint value: evmOft.owner or wallets.evm')
    return owner
}
