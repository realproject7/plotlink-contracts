// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {DeployBase} from "./DeployBase.s.sol";

contract DumpCurve is Script {
    function run() external {
        DeployBase deploy = new DeployBase();
        (uint128[] memory ranges, uint128[] memory prices) = deploy.generateCurve();

        bytes32 priceHash = keccak256(abi.encodePacked(prices));
        bytes32 rangeHash = keccak256(abi.encodePacked(ranges));

        console.log("Price hash:");
        console.logBytes32(priceHash);
        console.log("Range hash:");
        console.logBytes32(rangeHash);

        // Print spot-check prices at every 50th step
        console.log("--- Spot-check prices ---");
        for (uint256 i = 0; i < 500; i += 50) {
            console.log(i, prices[i]);
        }
    }
}
