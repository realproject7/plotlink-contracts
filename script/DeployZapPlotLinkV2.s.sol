// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ZapPlotLinkV2} from "../src/ZapPlotLinkV2.sol";

/// @title DeployZapPlotLinkV2 — Deploy ZapPlotLink v2 to Base Mainnet
contract DeployZapPlotLinkV2 is Script {
    // PLOT token on Base mainnet
    address constant PLOT_TOKEN = 0xF8A2C39111FCEB9C950aAf28A9E34EBaD99b85C1;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        ZapPlotLinkV2 zap = new ZapPlotLinkV2(PLOT_TOKEN);

        vm.stopBroadcast();

        console.log("ZapPlotLinkV2 deployed at:", address(zap));
        console.log("PLOT token:", PLOT_TOKEN);
        console.log("Owner:", vm.addr(deployerKey));
    }
}
