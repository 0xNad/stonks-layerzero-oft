import { expectedEvmOwner } from './invariant-policy'

describe('expectedEvmOwner', () => {
    it('uses the recorded contract owner after multisig handoff', () => {
        expect(
            expectedEvmOwner({
                wallets: { evm: '0xDeployer' },
                evmOft: { owner: '0xSafe' },
            })
        ).toBe('0xSafe')
    })

    it('uses the deployer before the ownership handoff is recorded', () => {
        expect(expectedEvmOwner({ wallets: { evm: '0xDeployer' }, evmOft: {} })).toBe('0xDeployer')
    })
})
