// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ZapPlotLinkV2} from "../src/ZapPlotLinkV2.sol";
import {IMCV2_Bond} from "../src/interfaces/IMCV2_Bond.sol";

/// @dev Extended ERC-20 interface for totalSupply
interface IERC20Extended is IERC20 {
    function totalSupply() external view returns (uint256);
}

/// @title E2EZapTest - End-to-end Zap trades on Base mainnet
/// @notice Executes real trades via ZapPlotLinkV2 for ETH, HUNT, USDC (if balance), PLOT,
///         and a sell flow back to PLOT. Logs tx hashes, input/output amounts.
contract E2EZapTest is Script {
    // -----------------------------------------------------------------------
    // Base mainnet addresses
    // -----------------------------------------------------------------------
    ZapPlotLinkV2 constant ZAP = ZapPlotLinkV2(payable(0x7bC192848003ab1Ba286C66AFD0dd8a1729c6b02));
    IMCV2_Bond constant BOND = IMCV2_Bond(0xc5a076cad94176c2996B32d8466Be1cE757FAa27);
    IERC20 constant PLOT = IERC20(0xF8A2C39111FCEB9C950aAf28A9E34EBaD99b85C1);
    IERC20 constant HUNT = IERC20(0x37f0c2915CeCC7e977183B8543Fc0864d03E064C);
    IERC20 constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    address constant ETH_ADDRESS = address(0);

    // Active storyline token (storyline ID 10 on mainnet StoryFactory)
    address constant STORYLINE_TOKEN = 0x72F4f07dfCec281b2DB5E04524c784Dac36B0aE7;

    // Trade amounts
    uint256 constant ETH_AMOUNT = 0.0001 ether;
    uint256 constant HUNT_AMOUNT = 10e18; // 10 HUNT
    uint256 constant USDC_AMOUNT = 1e6; // 1 USDC
    uint256 constant PLOT_AMOUNT = 10e18; // 10 PLOT

    uint256 scenariosPassed;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== E2E Zap Test Suite - Base Mainnet ===");
        console.log("Deployer:", deployer);
        console.log("Zap contract:", address(ZAP));
        console.log("Storyline token:", STORYLINE_TOKEN);
        console.log("");

        // Log balances
        console.log("--- Initial Balances ---");
        console.log("ETH:", deployer.balance);
        console.log("HUNT:", HUNT.balanceOf(deployer));
        console.log("USDC:", USDC.balanceOf(deployer));
        console.log("PLOT:", PLOT.balanceOf(deployer));
        console.log("");

        // ===== Estimation Tests =====
        _testEstimates();

        vm.startBroadcast(deployerKey);

        // Approvals
        PLOT.approve(address(ZAP), type(uint256).max);
        PLOT.approve(address(BOND), type(uint256).max);
        HUNT.approve(address(ZAP), type(uint256).max);
        USDC.approve(address(ZAP), type(uint256).max);
        IERC20(STORYLINE_TOKEN).approve(address(BOND), type(uint256).max);

        // ===== Zap Trades =====
        _testEthMint(deployer);
        _testHuntMint(deployer);
        _testUsdcMint(deployer);
        _testPlotMint(deployer);
        _testSell(deployer);

        vm.stopBroadcast();

        console.log("");
        console.log("=== ALL ZAP SCENARIOS PASSED ===");
        console.log("Scenarios passed:", scenariosPassed);
    }

    // ===================================================================
    // Estimation Tests (no broadcast needed - eth_call)
    // ===================================================================

    function _testEstimates() internal {
        console.log("--- Estimation Tests ---");

        // estimateMint: ETH
        (uint256 ethNeeded, uint256 plotReq1) = ZAP.estimateMint(ETH_ADDRESS, STORYLINE_TOKEN, 1e18);
        require(ethNeeded > 0, "EST-ETH: zero estimate");
        require(plotReq1 > 0, "EST-ETH: zero plot required");
        console.log("[EST-ETH] estimateMint(1 token)        PASS  ethNeeded=%d  plotReq=%d", ethNeeded, plotReq1);
        scenariosPassed++;

        // estimateMint: HUNT
        (uint256 huntNeeded, uint256 plotReq2) = ZAP.estimateMint(address(HUNT), STORYLINE_TOKEN, 1e18);
        require(huntNeeded > 0, "EST-HUNT: zero estimate");
        require(plotReq2 > 0, "EST-HUNT: zero plot required");
        console.log("[EST-HUNT] estimateMint(1 token)       PASS  huntNeeded=%d  plotReq=%d", huntNeeded, plotReq2);
        scenariosPassed++;

        // estimateMint: USDC
        (uint256 usdcNeeded, uint256 plotReq3) = ZAP.estimateMint(address(USDC), STORYLINE_TOKEN, 1e18);
        require(usdcNeeded > 0, "EST-USDC: zero estimate");
        require(plotReq3 > 0, "EST-USDC: zero plot required");
        console.log("[EST-USDC] estimateMint(1 token)       PASS  usdcNeeded=%d  plotReq=%d", usdcNeeded, plotReq3);
        scenariosPassed++;

        // estimateMintReverse: ETH
        (uint256 tokensOut1, uint256 plotAmt1) = ZAP.estimateMintReverse(ETH_ADDRESS, STORYLINE_TOKEN, ETH_AMOUNT);
        require(tokensOut1 > 0, "ESTR-ETH: zero tokens out");
        require(plotAmt1 > 0, "ESTR-ETH: zero plot amount");
        console.log("[ESTR-ETH] estimateMintReverse         PASS  tokensOut=%d  plotAmt=%d", tokensOut1, plotAmt1);
        scenariosPassed++;

        // estimateMintReverse: HUNT
        (uint256 tokensOut2, uint256 plotAmt2) = ZAP.estimateMintReverse(address(HUNT), STORYLINE_TOKEN, HUNT_AMOUNT);
        require(tokensOut2 > 0, "ESTR-HUNT: zero tokens out");
        require(plotAmt2 > 0, "ESTR-HUNT: zero plot amount");
        console.log("[ESTR-HUNT] estimateMintReverse        PASS  tokensOut=%d  plotAmt=%d", tokensOut2, plotAmt2);
        scenariosPassed++;

        // estimateMintReverse: USDC
        (uint256 tokensOut3, uint256 plotAmt3) = ZAP.estimateMintReverse(address(USDC), STORYLINE_TOKEN, USDC_AMOUNT);
        require(tokensOut3 > 0, "ESTR-USDC: zero tokens out");
        require(plotAmt3 > 0, "ESTR-USDC: zero plot amount");
        console.log("[ESTR-USDC] estimateMintReverse        PASS  tokensOut=%d  plotAmt=%d", tokensOut3, plotAmt3);
        scenariosPassed++;

        console.log("");
    }

    // ===================================================================
    // ETH -> Storyline Token (via Uniswap V4 single-hop)
    // ===================================================================

    function _testEthMint(address deployer) internal {
        console.log("--- ETH Zap Mint (mintReverse) ---");

        IERC20Extended storyToken = IERC20Extended(STORYLINE_TOKEN);
        uint256 storyBalBefore = storyToken.balanceOf(deployer);
        uint256 ethBalBefore = deployer.balance;

        uint256 tokensReceived = ZAP.mintReverse{value: ETH_AMOUNT}(ETH_ADDRESS, STORYLINE_TOKEN, ETH_AMOUNT, 0);

        uint256 ethSpent = ethBalBefore - deployer.balance;
        uint256 storyGained = storyToken.balanceOf(deployer) - storyBalBefore;

        require(storyGained > 0, "ETH: no storyline tokens received");
        require(storyGained == tokensReceived, "ETH: return value mismatch");
        console.log("[ZAP-ETH] mintReverse                  PASS  ethSpent=%d  tokensOut=%d", ethSpent, storyGained);
        scenariosPassed++;
    }

    // ===================================================================
    // HUNT -> Storyline Token (via MCV2 bonding curve, no Uniswap)
    // ===================================================================

    function _testHuntMint(address deployer) internal {
        console.log("--- HUNT Zap Mint (mintReverse) ---");

        if (HUNT.balanceOf(deployer) < HUNT_AMOUNT) {
            console.log("[ZAP-HUNT] SKIPPED - insufficient HUNT balance");
            return;
        }

        IERC20Extended storyToken = IERC20Extended(STORYLINE_TOKEN);
        uint256 storyBalBefore = storyToken.balanceOf(deployer);
        uint256 huntBalBefore = HUNT.balanceOf(deployer);

        uint256 tokensReceived = ZAP.mintReverse(address(HUNT), STORYLINE_TOKEN, HUNT_AMOUNT, 0);

        uint256 huntSpent = huntBalBefore - HUNT.balanceOf(deployer);
        uint256 storyGained = storyToken.balanceOf(deployer) - storyBalBefore;

        require(storyGained > 0, "HUNT: no storyline tokens received");
        require(storyGained == tokensReceived, "HUNT: return value mismatch");
        require(huntSpent == HUNT_AMOUNT, "HUNT: spent amount mismatch");
        console.log("[ZAP-HUNT] mintReverse                 PASS  huntSpent=%d  tokensOut=%d", huntSpent, storyGained);
        scenariosPassed++;
    }

    // ===================================================================
    // USDC -> Storyline Token (via Uniswap V4 multi-hop USDC->ETH->PLOT)
    // ===================================================================

    function _testUsdcMint(address deployer) internal {
        console.log("--- USDC Zap Mint (mintReverse) ---");

        if (USDC.balanceOf(deployer) < USDC_AMOUNT) {
            console.log("[ZAP-USDC] SKIPPED - insufficient USDC balance");
            return;
        }

        IERC20Extended storyToken = IERC20Extended(STORYLINE_TOKEN);
        uint256 storyBalBefore = storyToken.balanceOf(deployer);
        uint256 usdcBalBefore = USDC.balanceOf(deployer);

        uint256 tokensReceived = ZAP.mintReverse(address(USDC), STORYLINE_TOKEN, USDC_AMOUNT, 0);

        uint256 usdcSpent = usdcBalBefore - USDC.balanceOf(deployer);
        uint256 storyGained = storyToken.balanceOf(deployer) - storyBalBefore;

        require(storyGained > 0, "USDC: no storyline tokens received");
        require(storyGained == tokensReceived, "USDC: return value mismatch");
        require(usdcSpent == USDC_AMOUNT, "USDC: spent amount mismatch");
        console.log("[ZAP-USDC] mintReverse                 PASS  usdcSpent=%d  tokensOut=%d", usdcSpent, storyGained);
        scenariosPassed++;
    }

    // ===================================================================
    // PLOT -> Storyline Token (direct MCV2_Bond.mint via Zap)
    // ===================================================================

    function _testPlotMint(address deployer) internal {
        console.log("--- PLOT Zap Mint (mintReverse) ---");

        if (PLOT.balanceOf(deployer) < PLOT_AMOUNT) {
            console.log("[ZAP-PLOT] SKIPPED - insufficient PLOT balance");
            return;
        }

        IERC20Extended storyToken = IERC20Extended(STORYLINE_TOKEN);
        uint256 storyBalBefore = storyToken.balanceOf(deployer);
        uint256 plotBalBefore = PLOT.balanceOf(deployer);

        uint256 tokensReceived = ZAP.mintReverse(address(PLOT), STORYLINE_TOKEN, PLOT_AMOUNT, 0);

        uint256 plotSpent = plotBalBefore - PLOT.balanceOf(deployer);
        uint256 storyGained = storyToken.balanceOf(deployer) - storyBalBefore;

        require(storyGained > 0, "PLOT: no storyline tokens received");
        require(storyGained == tokensReceived, "PLOT: return value mismatch");
        console.log("[ZAP-PLOT] mintReverse                 PASS  plotSpent=%d  tokensOut=%d", plotSpent, storyGained);
        scenariosPassed++;
    }

    // ===================================================================
    // Sell: Storyline Token -> PLOT (via MCV2_Bond.burn)
    // ===================================================================

    function _testSell(address deployer) internal {
        console.log("--- Sell Flow (burn -> PLOT) ---");

        IERC20Extended storyToken = IERC20Extended(STORYLINE_TOKEN);
        uint256 storyBal = storyToken.balanceOf(deployer);

        if (storyBal == 0) {
            console.log("[SELL] SKIPPED - no storyline tokens to sell");
            return;
        }

        uint256 plotBalBefore = PLOT.balanceOf(deployer);

        // Sell all storyline tokens accumulated from previous tests
        (uint256 estRefund,) = BOND.getRefundForTokens(STORYLINE_TOKEN, storyBal);
        BOND.burn(STORYLINE_TOKEN, storyBal, 0, deployer);

        uint256 plotReceived = PLOT.balanceOf(deployer) - plotBalBefore;
        uint256 storyBalAfter = storyToken.balanceOf(deployer);

        require(storyBalAfter == 0, "SELL: storyline balance should be 0");
        require(plotReceived > 0, "SELL: no PLOT received");
        console.log(
            "[SELL] Burn all storyline tokens        PASS  burned=%d  plotReceived=%d  estimate=%d",
            storyBal,
            plotReceived,
            estRefund
        );
        scenariosPassed++;
    }
}
