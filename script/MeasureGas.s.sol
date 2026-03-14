// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StoryFactory} from "../src/StoryFactory.sol";

/// @title MeasureGas — Call createStoryline() and chainPlot() on deployed StoryFactory
/// @notice Run after DeployBaseSepolia to capture gas measurements.
///         Set STORY_FACTORY env var to the deployed address.
contract MeasureGas is Script {
    function run() external {
        address factoryAddr = vm.envAddress("STORY_FACTORY");
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        StoryFactory factory = StoryFactory(factoryAddr);

        vm.startBroadcast(deployerKey);

        // --- createStoryline ---
        uint256 gasStart = gasleft();
        uint256 storylineId = factory.createStoryline(
            "Gas Measurement Test Story",
            "QmTestCID00000000000000000000000000000000000000", // 50 chars, valid CID length
            keccak256("Genesis plot content for gas measurement"),
            true // hasDeadline
        );
        uint256 gasUsedCreate = gasStart - gasleft();

        console.log("--- createStoryline ---");
        console.log("Storyline ID:", storylineId);
        console.log("Gas used (approx in-script):", gasUsedCreate);

        // --- chainPlot ---
        gasStart = gasleft();
        factory.chainPlot(
            storylineId,
            "QmTestCID11111111111111111111111111111111111111", // 50 chars
            keccak256("Second plot content for gas measurement")
        );
        uint256 gasUsedChain = gasStart - gasleft();

        console.log("--- chainPlot ---");
        console.log("Gas used (approx in-script):", gasUsedChain);

        vm.stopBroadcast();
    }
}
