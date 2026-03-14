# Base Sepolia Deployment — StoryFactory

## Contract

| Field | Value |
|-------|-------|
| **StoryFactory** | `0x05C4d59529807316D6fA09cdaA509adDfe85b474` |
| **Chain** | Base Sepolia (84532) |
| **RPC** | `https://sepolia.base.org` |
| **Deploy TX** | `0xc980b687b7dac688ff6df1f25c74c6d293e36fd4bd589ce5def3c13236aedd57` |
| **Block** | 38854535 |
| **Deployer** | `0x017596303EE2F3C1250Aa67d2d33DBae1D1c4dBf` |

## Constructor Arguments

| Parameter | Value |
|-----------|-------|
| `_bond` (MCV2_Bond) | `0x5dfA75b0185efBaEF286E80B847ce84ff8a62C2d` |
| `_plotToken` (WETH) | `0x4200000000000000000000000000000000000006` |
| `_maxSupply` | `1,000,000e18` (1M tokens) |
| Step count | 500 |
| Curve | Mintpad Medium J-Curve (steepness 0.85, exponent 4) |
| Initial price | `2e12` wei (~0.000002 WETH, FDV ≈ 2 WETH ≈ $5,000) |
| Final price | `3,776,484,204,130,853` wei (~0.00378 WETH) |

## Gas Measurements

| Function | Gas Used | Notes |
|----------|----------|-------|
| **Deploy** | 13,599,048 | Contract creation with 500-step curve arrays |
| **createStoryline()** | 14,282,950 | Includes MCV2_Bond.createToken() with 500 bonding curve steps |
| **chainPlot()** | 39,826 | Storage write + event emission |

### Measurement Transactions

| Function | TX Hash |
|----------|---------|
| createStoryline | `0x26f85ccdecb905d815a89a22f869913fbfc208a4f9486a63451cc840813b933e` |
| chainPlot | `0x50b8f1dc1bc9442966b3981fb9ed228b87489ee52cb0d1ec09433820e6dbe55e` |

## Verification

Contract can be verified on Basescan Sepolia:
```bash
forge verify-contract 0x05C4d59529807316D6fA09cdaA509adDfe85b474 \
  src/StoryFactory.sol:StoryFactory \
  --chain-id 84532 \
  --constructor-args $(cast abi-encode "constructor(address,address,uint128,uint128[],uint128[])" \
    0x5dfA75b0185efBaEF286E80B847ce84ff8a62C2d \
    0x4200000000000000000000000000000000000006 \
    1000000000000000000000000 \
    "[<stepRanges>]" \
    "[<stepPrices>]")
```

## Notes

- `createStoryline()` gas is high (~14.3M) due to MCV2_Bond.createToken() deploying a new ERC20 and storing 500 bonding curve steps on-chain. This is expected behavior for Mint Club V2.
- `chainPlot()` gas (~40k) is well within the expected range for a storage write + event emission.
- Base Sepolia block gas limit is 60M, so both functions fit within a single block.
