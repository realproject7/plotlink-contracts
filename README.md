# PlotLink Contracts

On-chain storytelling protocol on Base. Writers create storylines backed by bonding curve tokens — every trade generates creator royalties, directly incentivizing authors to keep writing.

## How It Works

**StoryFactory** manages storylines and plots:
- `createStoryline()` — deploys a new MCV2 bonding curve token and stores the opening plot
- `chainPlot()` — appends subsequent plots (chapters) to an existing storyline
- `donate()` — direct tips from readers to writers

Each storyline token trades on a Mint Club V2 bonding curve with 5% creator royalties on every buy and sell.

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
| StoryFactory | [`0xfa5489b6710Ba2f8406b37fA8f8c3018e51FA229`](https://basescan.org/address/0xfa5489b6710Ba2f8406b37fA8f8c3018e51FA229) |
| ZapPlotLinkV2 | [`0x04f557F8D2806B34FC832a534c08DF514D4dfEeF`](https://basescan.org/address/0x04f557F8D2806B34FC832a534c08DF514D4dfEeF) |

## External Dependencies

| Contract | Address | Role |
|----------|---------|------|
| MCV2_Bond | `0xc5a076cad94176c2996B32d8466Be1cE757FAa27` | Bonding curve trading, token creation |
| MCV2_BondPeriphery | `0x492C412369Db76C9cdD9939e6C521579301473a3` | Reverse calculations for mint |
| PLOT | `0xF8A2C39111FCEB9C950aAf28A9E34EBaD99b85C1` | Protocol token (MCV2, backed by HUNT) |
| HUNT | `0x37f0c2915CeCC7e977183B8543Fc0864d03E064C` | Reserve token for PLOT |
| Uniswap V4 Universal Router | `0x6fF5693b99212Da76ad316178A184AB56D299b43` | Swap execution |
| Uniswap V4 Quoter | `0x0d5e0F971ED27FBfF6c2837bf31316121532048D` | Price estimation |
| ERC-8004 Registry | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` | Agent writer identity |

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

BSD-3-Clause
