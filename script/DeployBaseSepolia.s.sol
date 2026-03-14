// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StoryFactory} from "../src/StoryFactory.sol";

/// @title DeployBaseSepolia — Deploy StoryFactory to Base Sepolia
/// @notice Generates Mintpad Medium J-Curve (500 steps, steepness 0.85, exponent 4)
///         and deploys StoryFactory pointing at the real MCV2_Bond on Base Sepolia.
contract DeployBaseSepolia is Script {
    // Base Sepolia addresses
    address constant MCV2_BOND = 0x5dfA75b0185efBaEF286E80B847ce84ff8a62C2d;
    address constant PLOT_TOKEN = 0x4200000000000000000000000000000000000006; // WETH

    // Bonding curve parameters
    uint256 constant STEP_COUNT = 500;
    uint128 constant MAX_SUPPLY = 1_000_000e18;
    uint128 constant INITIAL_PRICE = 2e12; // ~$0.000005 WETH → FDV ≈ 2 WETH ≈ $5,000

    function run() external {
        // Generate bonding curve step arrays
        (uint128[] memory stepRanges, uint128[] memory stepPrices) = _generateCurve();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        StoryFactory factory = new StoryFactory(MCV2_BOND, PLOT_TOKEN, MAX_SUPPLY, stepRanges, stepPrices);

        vm.stopBroadcast();

        console.log("StoryFactory deployed at:", address(factory));
        console.log("Chain ID:", block.chainid);
        console.log("MCV2_Bond:", MCV2_BOND);
        console.log("PLOT_TOKEN:", PLOT_TOKEN);
        console.log("Step count:", STEP_COUNT);
        console.log("Max supply:", MAX_SUPPLY);
        console.log("Initial price:", INITIAL_PRICE);
        console.log("Final price:", stepPrices[STEP_COUNT - 1]);
    }

    /// @dev Mintpad Medium J-Curve: 500 steps, steepness 0.85, exponent 4
    ///      For step i: progress = i/500, scarcity = 1 - progress*0.85
    ///      multiplier = (1/scarcity)^4, price = INITIAL_PRICE * multiplier
    function _generateCurve() internal pure returns (uint128[] memory stepRanges, uint128[] memory stepPrices) {
        stepRanges = new uint128[](STEP_COUNT);
        stepPrices = new uint128[](STEP_COUNT);

        uint128 supplyPerStep = MAX_SUPPLY / uint128(STEP_COUNT);

        for (uint256 i = 0; i < STEP_COUNT; i++) {
            // Cumulative supply at end of this step
            if (i == STEP_COUNT - 1) {
                stepRanges[i] = MAX_SUPPLY; // snap last step
            } else {
                stepRanges[i] = supplyPerStep * uint128(i + 1);
            }

            // Price calculation using 1e18 fixed-point
            // scarcity = 1 - (i * 0.85 / 500) = 1 - (i * 85 / 50000)
            uint256 scarcity = 1e18 - (i * 85e18 / 50_000);

            // inv = 1 / scarcity (in 1e18 scale)
            uint256 inv = 1e36 / scarcity;

            // multiplier = inv^4 (in 1e18 scale)
            uint256 invSq = (inv * inv) / 1e18;
            uint256 multiplier = (invSq * invSq) / 1e18;

            // price = INITIAL_PRICE * multiplier / 1e18
            stepPrices[i] = uint128((uint256(INITIAL_PRICE) * multiplier) / 1e18);

            // Ensure price is never zero
            if (stepPrices[i] == 0) stepPrices[i] = 1;
        }
    }
}
