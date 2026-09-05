# Testnet Run Result

## Final status

PASS — COMPLETE OFT ADAPTER TESTNET PROOF

## Network pair

Solana Devnet <-> Robinhood Chain Testnet

Robinhood Chain Testnet was selected because live official LayerZero metadata, deployed bytecode, Endpoint EID 40451, Solana EID support, libraries, Executor, DVN pathway, and an Endpoint quote were all verified.

## Wallets and deployments

- Solana wallet: BTvyuzjPozDCLjvhjTsxgBfqeQoKgexEMRyyXvxvvUyN
- EVM wallet: 0x131625bbC0c0377812421Ca606dB8725f17ad931
- Dummy mint: G1RTxQsGTT9JNXuomStG8wVB6PrDWhPQwxrmvFDLcLrv
- Solana OFT Program: 6Zxe2WqArgpooREBXPFmyA3fGywgBRccFtYYePZ96tTF
- OFT Store: GJpYoSDb8oGuVviA8iQBm4GgffJidgdbSAWGNBP5mnJe
- Escrow: HKoFp6govaELQoKHEnaZfmcDF24Qzpk2JRkDtFAbQckR
- EVM OFT: 0x9F19D0491761Bfee5a32B73227F05FB1Fbd606b9
- EVM EndpointV2: 0x3aCAAf60502791D199a5a5F0B173D78229eBFe32
- EVM source verification: PASS
- Solana executable verification: PASS — local/deployed hash 08638531860e9bf3b394ae980511d5cac9a0cffbaa7cd2cad5ee509148665925

## Deployment and configuration transactions

- Solana token createMint: 4t18xqWGembWdGT6QCkKz6xAW9ZWYdoUYMkcZawMx6ZoFKhcDXnPmdh4MwUJjmjVXx1qH8D7tWmcLwYgKgS6nTCb
- Solana token createAta: 5yz5BMXtHCRsKUmsae1Pxt79xTM99G2pQsKcGPpgJbx2LF6uAV4KrwXcw6u9e5Wq2AWr2b4FUxGT2XcjKNQPiyST
- Solana token mintSupply: 4jc6mDLBopGbUeukKHxKg8PdCT2rtu14eJquE6DAUduJy8kXse6naSpaj5jM52eeHCnaaH9cSRGhQyFSwU9f64ax
- Solana token revokeAuthorities: 59vAUmkedeqLhGk8KzyuE6RBpuPhD9jJuV3CdqmEHJ5yrR4JB3yKZL86pNetgi7kvW7Ue7u4K5c5FVa8nrTCuY98
- Solana OFT program deployment: LPhEkzYzX2pSQ9wkmtUmfCfhzLxRcuFyRGUpoALUA9YdnKTjeTNUEuot79zPyUyqKitoifTAqfpUwbUo48y7t6q
- Solana OFT program deployment: 3WfGGmQexDjCcQRuqvS8nvMbNDiYFVh4uMNbSFbf8ZRjgJzDAWdfK8G4vzwA2a3a4Rc8QJ8XFRWUmspNyrcCFvGt
- Solana Adapter creation: 3HuaYQdqDie5gSN2jYogVstnBh4biAfjd2fcyZ5foXwxLAq1WwZvpDBrCrtWkf1CmwzPT5TENXHYGTXUqmcbePr8
- EVM OFT deployment: 0x475ad8325857864f501284f32be50fd58e9a400ce3c8040e3462538e10b0c38a
- LayerZero configuration: 4GM3d7aJioTbWeabnEeHAyuLm3PNfYce6mqqCzmpM2aSdVbev5uc627dQptkooSmPwPm3Bh1kCBZTjEMRFpqz97

## Cross-chain messages

|   # | Direction     | Amount (tSTONKS) | GUID                                                               | Source transaction                                                                       | Destination transaction                                                                  | Status    |
| --: | ------------- | ---------------: | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------- |
|   1 | SOLANA_TO_EVM |             1000 | 0xf335aafa675d9d3bb5392be700cd6314f38d03d39cfcf7f344a26fc5f775b3a6 | 8ZG5huvS3eteazyb6SULM9umiPyrunUgsFYgK5TmAoDify7PVoEeNfZpZA1pMCscJBEQrCyHnCfmSz3LKrfs2h4  | 0x5174684fc7f770c4ddb7f53439907d94fca839c4f843954b811a2fdcb55d5799                       | DELIVERED |
|   2 | EVM_TO_SOLANA |              400 | 0x2bc329db1dee8cf20c4b421caeed97e56ef92465a146b3f02ca4de23ed642a12 | 0x7f23b8440010ba71e4fcc23c9068c936a52979e3003b6e6af3ea194a7e7b798a                       | 5nsFbQ3YWiWvaFVVsyV1Dcjoi75BZFQt83bybaHrEmgp6J4Pu52F3wergVYmceyFkT4VFxQ31F2fMq3NcV4eSeKm | DELIVERED |
|   3 | SOLANA_TO_EVM |               10 | 0x7a90a50e6dff516fc339bf4c93eb1220a3e9a92a78b48d4ac3df05142c9df033 | 5pUricxUnzGQTG6ySQEgTDCzTcMv8PdJzxVwozSNSv7jbAhsYRUm4hJ1etk4CA8bF9XdGr5Ujnytcrga68KKnBXs | 0x630109f95d86149e1d7227ccef35ccded79130133054c3ea4d0866bee0043e88                       | DELIVERED |

## Before-and-after balances and supplies

### Message 1: SOLANA_TO_EVM

Before:

```json
{
  "capturedAt": "2026-09-05T16:51:59.053Z",
  "solana": {
    "userTokenRaw": "1000000000000000000",
    "escrowRaw": "0",
    "mintSupplyRaw": "1000000000000000000",
    "walletLamports": "2981005284"
  },
  "evm": {
    "userTokenRaw": "0",
    "totalSupplyRaw": "0",
    "walletWei": "9960288040000000"
  }
}
```

After:

```json
{
  "capturedAt": "2026-09-05T16:53:52.731Z",
  "solana": {
    "userTokenRaw": "999999000000000000",
    "escrowRaw": "1000000000000",
    "mintSupplyRaw": "1000000000000000000",
    "walletLamports": "2980478692"
  },
  "evm": {
    "userTokenRaw": "1000000000000000000000",
    "totalSupplyRaw": "1000000000000000000000",
    "walletWei": "9960288040000000"
  }
}
```

### Message 2: EVM_TO_SOLANA

Before:

```json
{
  "capturedAt": "2026-09-05T16:53:57.681Z",
  "solana": {
    "userTokenRaw": "999999000000000000",
    "escrowRaw": "1000000000000",
    "mintSupplyRaw": "1000000000000000000",
    "walletLamports": "2980478692"
  },
  "evm": {
    "userTokenRaw": "1000000000000000000000",
    "totalSupplyRaw": "1000000000000000000000",
    "walletWei": "9960288040000000"
  }
}
```

After:

```json
{
  "capturedAt": "2026-09-05T16:55:51.427Z",
  "solana": {
    "userTokenRaw": "999999400000000000",
    "escrowRaw": "600000000000",
    "mintSupplyRaw": "1000000000000000000",
    "walletLamports": "2980478692"
  },
  "evm": {
    "userTokenRaw": "600000000000000000000",
    "totalSupplyRaw": "600000000000000000000",
    "walletWei": "9788335871826600"
  }
}
```

### Message 3: SOLANA_TO_EVM

Before:

```json
{
  "capturedAt": "2026-09-05T16:55:56.453Z",
  "solana": {
    "userTokenRaw": "999999400000000000",
    "escrowRaw": "600000000000",
    "mintSupplyRaw": "1000000000000000000",
    "walletLamports": "2980478692"
  },
  "evm": {
    "userTokenRaw": "600000000000000000000",
    "totalSupplyRaw": "600000000000000000000",
    "walletWei": "9788335871826600"
  }
}
```

After:

```json
{
  "capturedAt": "2026-09-05T16:57:40.598Z",
  "solana": {
    "userTokenRaw": "999999390000000000",
    "escrowRaw": "610000000000",
    "mintSupplyRaw": "1000000000000000000",
    "walletLamports": "2979953229"
  },
  "evm": {
    "userTokenRaw": "610000000000000000000",
    "totalSupplyRaw": "610000000000000000000",
    "walletWei": "9788335871826600"
  }
}
```

## Supply invariants

```json
{
  "status": "PASS",
  "normalizedEscrowShared": "610000000",
  "evmSupplyShared": "610000000",
  "solanaSupplyBeforeRaw": "1000000000000000000",
  "solanaSupplyAfterRaw": "1000000000000000000",
  "solanaUserRaw": "999999390000000000",
  "solanaEscrowRaw": "610000000000",
  "checkedAt": "2026-09-05T17:01:41.351Z",
  "checks": {
    "mintAuthorityRevoked": true,
    "freezeAuthorityRevoked": true,
    "solanaSupplyUnchanged": true,
    "circulatingPlusEscrowEqualsFixedSupply": true,
    "normalizedEscrowEqualsEvmSupply": true,
    "solanaEscrowHasNoDust": true,
    "evmSupplyHasNoDust": true,
    "evmUserOwnsOutstandingSupply": true,
    "evmMetadataCorrect": true,
    "evmOwnerCorrect": true,
    "evmEndpointCorrect": true,
    "solanaDustCleaning": true,
    "evmDustCleaning": true
  }
}
```

## Run another round trip

```bash
ROUNDTRIP_ONLY=1 S2E_AMOUNT=10 E2S_AMOUNT=10 ./run-testnet-e2e.sh
```

## Unresolved limitations

- None

The run is complete only after deterministic Solana executable verification, EVM source verification, delivery in both directions, supply-invariant checks, and authority handoff all pass.
