# Tool and dependency versions

## Reproducible pins

| Component                            | Version or pin                                    |
| ------------------------------------ | ------------------------------------------------- |
| LayerZero devtools source            | commit `4973ba8bef7b0fdf7268469abea3ea50dbd4bbd8` |
| Official source example              | `examples/oft-solana` version `0.12.11`           |
| Node.js project floor                | `20.19.5` (`.nvmrc`)                              |
| pnpm                                 | `8.15.6` (`packageManager`)                       |
| Rust                                 | `1.84.1` (`rust-toolchain.toml`)                  |
| Solana CLI                           | `2.2.20`                                          |
| Anchor CLI                           | `0.31.1`                                          |
| solana-verify                        | `0.5.1`                                           |
| Solidity                             | `0.8.22`, optimizer enabled, 200 runs             |
| Hardhat                              | `2.26.4` resolved                                 |
| Hardhat Verify                       | `2.1.3`                                           |
| LayerZero definitions                | `3.1.10`                                          |
| LayerZero protocol and Solana cohort | `3.0.168`                                         |
| LayerZero OFT EVM                    | `4.0.1`                                           |
| ethers                               | `5.7.2`                                           |
| Squads multisig SDK                  | `2.1.4`                                           |
| Safe Protocol Kit                    | `8.0.6`                                           |
| Safe deployments                     | `1.37.62`                                         |

The lockfile is authoritative for transitive dependencies. LayerZero direct packages that share protocol types are kept on a compatible cohort rather than upgraded independently.

## Reproducible Solana build

Docker must be running, then:

```bash
./scripts/build-solana-verifiable.sh
./scripts/verify-solana-source.sh
```

The second command compares the executable hash of the local binary with the deployed program and records both hashes.

## Version evidence

```bash
node --version
pnpm dlx pnpm@8.15.6 --version
rustc --version
cargo --version
solana --version
anchor --version
solana-verify --version
docker version
pnpm dlx pnpm@8.15.6 hardhat --version
pnpm dlx pnpm@8.15.6 list --depth 0
```

The host may have a newer Node or pnpm. Project wrappers invoke pnpm `8.15.6` explicitly and do not mutate global tools.
