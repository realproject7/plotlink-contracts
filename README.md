# PlotLink Contracts

On-chain storytelling protocol on Base. Writers create storylines backed by bonding curve tokens — every trade generates creator royalties, directly incentivizing authors to keep writing.

## How It Works

**StoryFactory** manages storylines and plots:
- `createStoryline()` — deploys a new MCV2 bonding curve token and stores the opening plot
- `chainPlot()` — appends subsequent plots (chapters) to an existing storyline
- `donate()` — direct tips from readers to writers

Each storyline token trades on a Mint Club V2 bonding curve with 1% creator royalties on mint and 1% on burn.

**ZapPlotLinkV2** enables one-click purchases with any supported token:

| Input | Route | Uniswap needed? |
|-------|-------|-----------------|
| ETH | Uniswap V4 single-hop (ETH/PLOT pool) → MCV2_Bond | Yes |
| USDC | Uniswap V4 multi-hop (USDC→ETH→PLOT) → MCV2_Bond | Yes |
| HUNT | MCV2 bonding curve (HUNT→PLOT, HUNT is PLOT's reserve) → MCV2_Bond | No |
| PLOT | Direct MCV2_Bond.mint | No |

## Deployed Contracts (Base Mainnet)

| Contract | Address |
|----------|---------|
| StoryFactory (v4b, symbol-collision fix) | [`0x9D2AE1E99D0A6300bfcCF41A82260374e38744Cf`](https://basescan.org/address/0x9D2AE1E99D0A6300bfcCF41A82260374e38744Cf) |
| StoryFactory (v1, deprecated) | [`0x337c5b96f03fB335b433291695A4171fd5dED8B0`](https://basescan.org/address/0x337c5b96f03fB335b433291695A4171fd5dED8B0) |
| ZapPlotLinkV2 | [`0xAe50C9444DA2Ac80B209dC8B416d1B4A7D3939B0`](https://basescan.org/address/0xAe50C9444DA2Ac80B209dC8B416d1B4A7D3939B0) |

## External Dependencies

| Contract | Address | Role |
|----------|---------|------|
| MCV2_Bond | `0xc5a076cad94176c2996B32d8466Be1cE757FAa27` | Bonding curve trading, token creation |
| MCV2_BondPeriphery | `0x492C412369Db76C9cdD9939e6C521579301473a3` | Reverse calculations for mint |
| PLOT | `0x4F567DACBF9D15A6acBe4A47FC2Ade0719Fb63C4` | Protocol token (MCV2, backed by HUNT) |
| HUNT | `0x37f0c2915CeCC7e977183B8543Fc0864d03E064C` | Reserve token for PLOT |
| Uniswap V4 Universal Router | `0x6fF5693b99212Da76ad316178A184AB56D299b43` | Swap execution |
| Uniswap V4 Quoter | `0x0d5e0F971ED27FBfF6c2837bf31316121532048D` | Price estimation |
## Build

```bash
forge build
```

## Test

```bash
# Unit tests
forge test

# E2E on Base mainnet (requires DEPLOYER_PRIVATE_KEY in .env)
forge script script/E2ETest.s.sol --rpc-url https://mainnet.base.org --broadcast

# E2E Zap trades on Base mainnet
forge script script/E2EZapTest.s.sol --rpc-url https://mainnet.base.org --broadcast --slow
```

## Deploy

```bash
# StoryFactory
forge script script/DeployBase.s.sol --rpc-url https://mainnet.base.org --broadcast --verify --verifier sourcify

# ZapPlotLinkV2
forge script script/DeployZapPlotLinkV2.s.sol --rpc-url https://mainnet.base.org --broadcast --verify --verifier sourcify

# Create PLOT/ETH Uniswap V4 pool
forge script script/CreatePlotEthPool.s.sol --rpc-url https://mainnet.base.org --broadcast
```

## Project Structure

```
src/
├── StoryFactory.sol          Storyline + plot management
├── ZapPlotLinkV2.sol         Multi-token zap (ETH/USDC/HUNT/PLOT → storyline token)
├── ZapPlotLink.sol           V1 zap (deprecated)
└── interfaces/
    ├── IMCV2_Bond.sol        Mint Club V2 interface
    ├── IZapInterfaces.sol    Uniswap V4 + MCV2 interfaces for Zap
    └── IERC20.sol            ERC-20 interface

script/
├── DeployBase.s.sol          Deploy StoryFactory to Base mainnet
├── DeployZapPlotLinkV2.s.sol Deploy ZapPlotLinkV2 to Base mainnet
├── CreatePlotEthPool.s.sol   Create PLOT/ETH Uniswap V4 pool
├── E2ETest.s.sol             End-to-end StoryFactory lifecycle
├── E2EZapTest.s.sol          End-to-end Zap trading tests
└── ...                       Testnet deploy, gas measurement, curve utilities
```

## License

MIT
