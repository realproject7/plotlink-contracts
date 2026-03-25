// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployBase} from "../script/DeployBase.s.sol";

/// @title DeployBaseTest — Validate the mainnet J-curve (hardcoded from story-token-curve.txt)
contract DeployBaseTest is Test {
    DeployBase deploy;

    function setUp() public {
        deploy = new DeployBase();
    }

    function test_curveLength() public view {
        (uint128[] memory ranges, uint128[] memory prices) = deploy.getCurve();
        assertEq(ranges.length, 500);
        assertEq(prices.length, 500);
    }

    function test_curveSupplyUniform() public view {
        (uint128[] memory ranges,) = deploy.getCurve();

        // First step: 2,000 tokens
        assertEq(ranges[0], 2_000e18);
        // Second step: 4,000 tokens
        assertEq(ranges[1], 4_000e18);
        // Step 250: 502,000 tokens (midpoint)
        assertEq(ranges[249], 500_000e18);
        // Last step: exactly MAX_SUPPLY
        assertEq(ranges[499], 1_000_000e18);
        // Second-to-last: 998,000
        assertEq(ranges[498], 998_000e18);
    }

    function test_curveFirstPrice() public view {
        (, uint128[] memory prices) = deploy.getCurve();
        // Step 0 = 0.001 PLOT
        assertEq(prices[0], 1e15);
    }

    function test_curveFinalPriceExact() public view {
        (, uint128[] memory prices) = deploy.getCurve();
        // Step 499 = exactly 1.8882421 PLOT (hardcoded)
        assertEq(prices[499], 1_888_242_100_000_000_000);
    }

    function test_curveMonotonicallyIncreasing() public view {
        (, uint128[] memory prices) = deploy.getCurve();
        for (uint256 i = 1; i < 500; i++) {
            assertTrue(prices[i] >= prices[i - 1], "Price must be monotonically increasing");
        }
    }

    function test_curvePenultimatePriceCloseToFinal() public view {
        (, uint128[] memory prices) = deploy.getCurve();
        // J-curve: steeper near the end. Step 498 should be less than final.
        uint256 penultimate = prices[498];
        uint256 final_ = prices[499];
        assertTrue(penultimate < final_, "Penultimate price should be less than final");
        // Allow up to 5% gap for J-curve steepness
        uint256 ratio = (penultimate * 1e18) / final_;
        assertTrue(ratio > 0.95e18, "Penultimate price too far from final");
    }

    function test_curveMidpointInRange() public view {
        (, uint128[] memory prices) = deploy.getCurve();
        // Step 250 (midpoint) should be between initial and final
        assertTrue(prices[250] > prices[0], "Midpoint should exceed initial");
        assertTrue(prices[250] < prices[499], "Midpoint should be below final");
        // J-curve midpoint from curve file
        assertEq(prices[250], 9_148_100_000_000_000);
    }

    function test_curveNoPriceIsZero() public view {
        (, uint128[] memory prices) = deploy.getCurve();
        for (uint256 i = 0; i < 500; i++) {
            assertTrue(prices[i] > 0, "Price must be non-zero");
        }
    }

    /// @dev Full-table snapshot: keccak256 of the entire packed price and range arrays.
    ///      Any change to the curve (growth rate, rounding, step count) breaks this test.
    ///      Regenerate hashes via: forge script script/DumpCurve.s.sol:DumpCurve
    function test_curveFullTableSnapshot() public view {
        (uint128[] memory ranges, uint128[] memory prices) = deploy.getCurve();

        bytes32 priceHash = keccak256(abi.encodePacked(prices));
        bytes32 rangeHash = keccak256(abi.encodePacked(ranges));

        assertEq(priceHash, 0x680fad91da1e7b66d6585321b4cb8498ecaee51a8e782a48dc8538382a2f39e5);
        assertEq(rangeHash, 0x2fa88b79c2a4811f9e33b02deb52b4991e4dcdf78fc23a2529e5b3fb22194844);
    }

    /// @dev Spot-check 10 evenly-spaced prices across the curve to catch drift
    function test_curveSpotCheckPrices() public view {
        (, uint128[] memory prices) = deploy.getCurve();

        assertEq(prices[0], 1_000_000_000_000_000);
        assertEq(prices[50], 1_426_600_000_000_000);
        assertEq(prices[100], 2_107_100_000_000_000);
        assertEq(prices[150], 3_246_200_000_000_000);
        assertEq(prices[200], 5_270_200_000_000_000);
        assertEq(prices[250], 9_148_100_000_000_000);
        assertEq(prices[300], 17_346_700_000_000_000);
        assertEq(prices[350], 37_168_900_000_000_000);
        assertEq(prices[400], 95_367_400_000_000_000);
        assertEq(prices[450], 327_890_300_000_000_000);
    }
}
