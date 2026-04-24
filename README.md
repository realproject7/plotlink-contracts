<div align="center">

# PlotLink Contracts

### On-chain storytelling protocol on Base.

<p>
  <a href="https://plotlink.xyz"><img src="https://img.shields.io/badge/live-plotlink.xyz-8B4513" alt="live" /></a>
  <img src="https://img.shields.io/badge/chain-Base_(L2)-0052FF" alt="Base" />
  <img src="https://img.shields.io/badge/framework-Foundry-orange" alt="Foundry" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="AGPL-3.0" /></a>
</p>

<p>
  <a href="https://github.com/realproject7/plotlink"><strong>Web App</strong></a> ·
  <a href="https://github.com/realproject7/plotlink-ows"><strong>AI Writer</strong></a> ·
  <a href="#deployed-contracts"><strong>Contracts</strong></a>
</p>

</div>

---

## Overview

Writers create storylines backed by bonding curve tokens — every mint generates creator royalties, directly incentivizing authors to keep writing.

**StoryFactory** manages storylines and plots:
- `createStoryline()` — deploys a new MCV2 bonding curve token and stores the opening plot on IPFS
- `chainPlot()` — appends subsequent chapters to an existing storyline
- `donate()` — direct tips from readers to writers

Each storyline token trades on a **Mint Club V2 bonding curve** with 1% creator royalties on mint and 1% on burn (set in the contract as `MINT_ROYALTY = 100` and `BURN_ROYALTY = 100` basis points).

## Zap: One-Click Minting

**ZapPlotLinkV2** enables minting story tokens with any supported token in a single transaction:

| Input | Route | Uniswap needed? |
|-------|-------|-----------------|
| ETH | Uniswap V4 single-hop (ETH/PLOT pool) → MCV2_Bond | Yes |
| USDC | Uniswap V4 multi-hop (USDC→ETH→PLOT) → MCV2_Bond | Yes |
| HUNT | MCV2 bonding curve (HUNT→PLOT, HUNT is PLOT's reserve) → MCV2_Bond | No |
| PLOT | Direct MCV2_Bond.mint | No |

## Deployed Contracts

### PlotLink (Base Mainnet)

| Contract | Address |
|----------|---------|
| StoryFactory (v4b) | [`0x9D2AE1E99D0A6300bfcCF41A82260374e38744Cf`](https://basescan.org/address/0x9D2AE1E99D0A6300bfcCF41A82260374e38744Cf) |
| ZapPlotLinkV2 | [`0xAe50C9444DA2Ac80B209dC8B416d1B4A7D3939B0`](https://basescan.org/address/0xAe50C9444DA2Ac80B209dC8B416d1B4A7D3939B0) |

### External Dependencies (Base Mainnet)

| Contract | Address | Role |
|----------|---------|------|
| MCV2_Bond | [`0xc5a076cad94176c2996B32d8466Be1cE757FAa27`](https://basescan.org/address/0xc5a076cad94176c2996B32d8466Be1cE757FAa27) | Bonding curve, token creation |
| PLOT | [`0x4F567DACBF9D15A6acBe4A47FC2Ade0719Fb63C4`](https://basescan.org/address/0x4F567DACBF9D15A6acBe4A47FC2Ade0719Fb63C4) | Protocol token (backed by HUNT) |
| HUNT | [`0x37f0c2915CeCC7e977183B8543Fc0864d03E064C`](https://basescan.org/address/0x37f0c2915CeCC7e977183B8543Fc0864d03E064C) | Reserve token for PLOT |
| ERC-8004 Registry | [`0x8004A169FB4a3325136EB29fA0ceB6D2e539a432`](https://basescan.org/address/0x8004A169FB4a3325136EB29fA0ceB6D2e539a432) | AI agent identity |
| Uniswap V4 Universal Router | [`0x6fF5693b99212Da76ad316178A184AB56D299b43`](https://basescan.org/address/0x6fF5693b99212Da76ad316178A184AB56D299b43) | Swap execution |

## Project Structure

```
src/
├── StoryFactory.sol          Storyline + plot management, royalty config
├── ZapPlotLinkV2.sol         Multi-token zap (ETH/USDC/HUNT/PLOT → story token)
└── interfaces/
    ├── IMCV2_Bond.sol        Mint Club V2 bonding curve interface
    ├── IZapInterfaces.sol    Uniswap V4 + MCV2 interfaces for Zap
    └── IERC20.sol            ERC-20 interface

script/
├── DeployBase.s.sol          Deploy StoryFactory to Base mainnet
├── DeployZapPlotLinkV2.s.sol Deploy ZapPlotLinkV2 to Base mainnet
├── CreatePlotEthPool.s.sol   Create PLOT/ETH Uniswap V4 pool
├── E2ETest.s.sol             End-to-end StoryFactory lifecycle test
└── E2EZapTest.s.sol          End-to-end Zap trading test
```

## Development

```bash
forge build          # Compile contracts
forge test           # Run unit tests
```

### E2E Tests (requires Base mainnet RPC + deployer key)

```bash
# StoryFactory lifecycle
forge script script/E2ETest.s.sol --rpc-url https://mainnet.base.org --broadcast

# Zap trading
forge script script/E2EZapTest.s.sol --rpc-url https://mainnet.base.org --broadcast --slow
```

### Deploy

```bash
# StoryFactory
forge script script/DeployBase.s.sol --rpc-url https://mainnet.base.org --broadcast --verify --verifier sourcify

# ZapPlotLinkV2
forge script script/DeployZapPlotLinkV2.s.sol --rpc-url https://mainnet.base.org --broadcast --verify --verifier sourcify
```

## Related Repositories

| Repo | Description |
|------|-------------|
| [plotlink](https://github.com/realproject7/plotlink) | Web app — frontend, indexer, airdrop |
| [plotlink-ows](https://github.com/realproject7/plotlink-ows) | AI Writer — local CLI for story writing |

## License

[AGPL-3.0](LICENSE)
