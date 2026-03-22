// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PLTest} from "../src/PLTest.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";

/// @title DeployPLTestAndPool — Deploy PL_TEST token + Uniswap V4 pool on Base Sepolia
/// @notice Creates PL_TEST ERC-20, initializes a V4 pool (PL_TEST/WETH), and seeds liquidity.
contract DeployPLTestAndPool is Script {
    // Base Sepolia Uniswap V4 addresses
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant POSITION_MANAGER = 0x4B2C77d209D3405F41a037Ec6c77F7F5b8e2ca80;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // Pool parameters
    uint24 constant POOL_FEE = 3000; // 0.30%
    int24 constant TICK_SPACING = 60;

    // Liquidity seed amounts
    uint256 constant PL_TEST_SEED = 100e18; // 100 PL_TEST
    uint256 constant WETH_SEED = 0.005 ether; // 0.005 ETH

    // Initial supply for PL_TEST
    uint256 constant INITIAL_SUPPLY = 10_000e18; // 10,000 PL_TEST

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Deploy PL_TEST token
        PLTest plTest = new PLTest(INITIAL_SUPPLY);
        console.log("PL_TEST deployed at:", address(plTest));

        // 2. Sort tokens for PoolKey (currency0 < currency1)
        (address token0, address token1) = _sortTokens(address(plTest), WETH);
        bool plTestIsToken0 = token0 == address(plTest);

        // 3. Build pool key
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        // 4. Initialize pool
        uint160 sqrtPriceX96 = _getSqrtPrice(plTestIsToken0);
        int24 tick = IPoolManager(POOL_MANAGER).initialize(poolKey, sqrtPriceX96);
        console.log("Pool initialized at tick:");
        console.logInt(tick);

        // 5. Approvals
        plTest.approve(PERMIT2, type(uint256).max);
        IWETH(WETH).deposit{value: WETH_SEED}();
        IWETH(WETH).approve(PERMIT2, type(uint256).max);
        IPermit2(PERMIT2).approve(address(plTest), POSITION_MANAGER, type(uint160).max, type(uint48).max);
        IPermit2(PERMIT2).approve(WETH, POSITION_MANAGER, type(uint160).max, type(uint48).max);

        // 6. Add liquidity
        _addLiquidity(poolKey, tick, sqrtPriceX96, plTestIsToken0, deployer);

        vm.stopBroadcast();

        console.log("Pool Key:");
        console.log("  currency0:", token0);
        console.log("  currency1:", token1);
    }

    function _sortTokens(address a, address b) internal pure returns (address token0, address token1) {
        if (uint160(a) < uint160(b)) {
            token0 = a;
            token1 = b;
        } else {
            token0 = b;
            token1 = a;
        }
    }

    function _getSqrtPrice(bool plTestIsToken0) internal pure returns (uint160) {
        // Price: 100 PL_TEST = 0.005 WETH => 1 PL_TEST = 0.00005 WETH
        if (plTestIsToken0) {
            // price = token1/token0 = WETH/PL_TEST = 0.00005
            // sqrt(0.00005) * 2^96 ≈ 560_228_142_366_059_520
            return 560_228_142_366_059_520;
        } else {
            // price = token1/token0 = PL_TEST/WETH = 20000
            // sqrt(20000) * 2^96 ≈ 11_204_562_847_321_190_656_000
            return uint160(11_204_562_847_321_190_656_000);
        }
    }

    function _addLiquidity(
        PoolKey memory poolKey,
        int24 tick,
        uint160 sqrtPriceX96,
        bool plTestIsToken0,
        address deployer
    ) internal {
        int24 tickLower = ((tick - 6000) / TICK_SPACING) * TICK_SPACING;
        int24 tickUpper = ((tick + 6000) / TICK_SPACING) * TICK_SPACING;

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        uint256 amt0 = plTestIsToken0 ? PL_TEST_SEED : WETH_SEED;
        uint256 amt1 = plTestIsToken0 ? WETH_SEED : PL_TEST_SEED;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96, sqrtLower, sqrtUpper, amt0, amt1);

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amt0, amt1, deployer, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        IPositionManager(POSITION_MANAGER).modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);

        console.log("Liquidity seeded:", liquidity);
    }
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}
