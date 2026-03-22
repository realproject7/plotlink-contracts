// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ZapPlotLink} from "../src/ZapPlotLink.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/// @title DeployZapPlotLink — Deploy ZapPlotLink contract on Base Sepolia
/// @notice Reads PL_TEST and pool addresses from env vars set after P5-8a deployment.
contract DeployZapPlotLink is Script {
    // Base Sepolia addresses (fixed)
    address constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    address constant MCV2_BOND = 0x5dfA75b0185efBaEF286E80B847ce84ff8a62C2d;
    address constant MCV2_BOND_PERIPHERY = 0x20fBC8a650d75e4C2Dab8b7e85C27135f0D64e89;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    // Pool parameters (must match pool creation)
    uint24 constant POOL_FEE = 3000;
    int24 constant TICK_SPACING = 60;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address plTestAddr = vm.envAddress("PL_TEST_ADDRESS");

        // Sort tokens for PoolKey
        address token0;
        address token1;
        if (uint160(plTestAddr) < uint160(WETH)) {
            token0 = plTestAddr;
            token1 = WETH;
        } else {
            token0 = WETH;
            token1 = plTestAddr;
        }

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        vm.startBroadcast(deployerKey);

        ZapPlotLink zap = new ZapPlotLink(POOL_MANAGER, MCV2_BOND, MCV2_BOND_PERIPHERY, WETH, plTestAddr, poolKey);

        vm.stopBroadcast();

        console.log("ZapPlotLink deployed at:", address(zap));
        console.log("PL_TEST:", plTestAddr);
        console.log("Pool currency0:", token0);
        console.log("Pool currency1:", token1);
    }
}
