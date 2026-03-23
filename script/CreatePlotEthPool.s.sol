// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title CreatePlotEthPool — Create and seed PLOT/ETH Uniswap V4 pool on Base Mainnet
/// @notice Creates a native-ETH / PLOT pool (fee 3000, tick spacing 60) and seeds initial liquidity.
///         The pool uses native ETH (address(0)), matching ZapPlotLinkV2's routing.
contract CreatePlotEthPool is Script {
    // Base Mainnet Uniswap V4 addresses
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Tokens
    address constant PLOT = 0xF8A2C39111FCEB9C950aAf28A9E34EBaD99b85C1;
    address constant NATIVE_ETH = address(0);

    // Pool parameters (must match ZapPlotLinkV2 config)
    uint24 constant POOL_FEE = 3000; // 0.30%
    int24 constant TICK_SPACING = 60;

    // Liquidity seed amounts (small initial liquidity)
    uint256 constant PLOT_SEED = 1_000e18; // 1,000 PLOT
    uint256 constant ETH_SEED = 0.001 ether; // 0.001 ETH

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Native ETH is always address(0), which is < any ERC-20 address
        address token0 = NATIVE_ETH;
        address token1 = PLOT;

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        // Initial price: 1,000 PLOT = 0.001 ETH → 1 PLOT = 0.000001 ETH
        // price (token1/token0) = PLOT/ETH ... wait, V4 price = token1/token0
        // token0 = ETH (address(0)), token1 = PLOT
        // Initial price: 1 ETH = 1,000,000 PLOT → tick ≈ 138163, rounded to spacing
        int24 initTick = int24(138_120);
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(initTick);

        vm.startBroadcast(deployerKey);

        // 1. Initialize the pool
        int24 tick = IPoolManager(POOL_MANAGER).initialize(poolKey, sqrtPriceX96);
        console.log("Pool initialized at tick:");
        console.logInt(tick);

        // 2. Approvals for PLOT via Permit2
        IERC20(PLOT).approve(PERMIT2, type(uint256).max);
        IPermit2(PERMIT2).approve(PLOT, POSITION_MANAGER, type(uint160).max, type(uint48).max);

        // 3. Add liquidity around current tick
        _addLiquidity(poolKey, tick, sqrtPriceX96, deployer);

        vm.stopBroadcast();

        console.log("Pool Key:");
        console.log("  currency0 (ETH):", token0);
        console.log("  currency1 (PLOT):", token1);
        console.log("  fee:", POOL_FEE);
        console.logInt(TICK_SPACING);
    }

    function _addLiquidity(PoolKey memory poolKey, int24 tick, uint160 sqrtPriceX96, address deployer) internal {
        int24 tickLower = ((tick - 6000) / TICK_SPACING) * TICK_SPACING;
        int24 tickUpper = ((tick + 6000) / TICK_SPACING) * TICK_SPACING;

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // token0 = ETH, token1 = PLOT
        uint128 liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, ETH_SEED, PLOT_SEED);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, ETH_SEED, PLOT_SEED, deployer, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(Currency.wrap(NATIVE_ETH), deployer, 0);

        IPositionManager(POSITION_MANAGER).modifyLiquidities{value: ETH_SEED}(
            abi.encode(actions, params), block.timestamp + 120
        );

        console.log("Liquidity seeded:", liquidity);
    }
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}
