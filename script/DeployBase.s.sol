// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StoryFactory} from "../src/StoryFactory.sol";

/// @title DeployBase — Deploy StoryFactory to Base mainnet
/// @notice Generates an exponential bonding curve (500 steps, 0.001 → 1.8882421 PL_TEST)
///         and deploys StoryFactory pointing at the real MCV2_Bond on Base mainnet.
contract DeployBase is Script {
    // Base mainnet addresses
    address constant MCV2_BOND = 0xc5a076cad94176c2996B32d8466Be1cE757FAa27;
    address constant PL_TEST = 0xF8A2C39111FCEB9C950aAf28A9E34EBaD99b85C1;

    // Bonding curve parameters
    uint256 constant STEP_COUNT = 500;
    uint128 constant MAX_SUPPLY = 1_000_000e18;
    uint128 constant SUPPLY_PER_STEP = 2_000e18; // uniform 2,000 token increments
    uint128 constant INITIAL_PRICE = 1e15; // 0.001 PL_TEST

    function run() external {
        (uint128[] memory stepRanges, uint128[] memory stepPrices) = generateCurve();

        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        StoryFactory factory = new StoryFactory(MCV2_BOND, PL_TEST, MAX_SUPPLY, stepRanges, stepPrices, 8);

        vm.stopBroadcast();

        console.log("StoryFactory deployed at:", address(factory));
        console.log("Chain ID:", block.chainid);
        console.log("MCV2_Bond:", MCV2_BOND);
        console.log("PL_TEST:", PL_TEST);
        console.log("Step count:", STEP_COUNT);
        console.log("Max supply:", MAX_SUPPLY);
        console.log("Initial price:", stepPrices[0]);
        console.log("Final price:", stepPrices[STEP_COUNT - 1]);
    }

    /// @dev Exponential curve: 500 steps from 0.001 to ~1.8882421 PL_TEST per token
    ///      Supply increments: uniform 2,000 tokens per step (2000, 4000, ..., 1_000_000)
    ///      Price: INITIAL_PRICE * MULTIPLIER^i where MULTIPLIER = e^(ln(1888.2421)/499)
    ///      Source of truth: issue #20 discussion (multiplier with ~40k wei max drift)
    function generateCurve() public pure returns (uint128[] memory stepRanges, uint128[] memory stepPrices) {
        stepRanges = new uint128[](STEP_COUNT);
        stepPrices = new uint128[](STEP_COUNT);

        // e^(ln(1888.2421)/499) in 1e18 fixed-point — from issue #20 discussion
        uint256 multiplier = 1_015_231_877_572_578_560;

        uint256 price = uint256(INITIAL_PRICE);

        for (uint256 i = 0; i < STEP_COUNT; i++) {
            stepRanges[i] = uint128(SUPPLY_PER_STEP * (i + 1));
            stepPrices[i] = uint128(price);
            if (i < STEP_COUNT - 1) {
                price = (price * multiplier) / 1e18;
            }
        }
    }
}
