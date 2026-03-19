// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DeployBase} from "../script/DeployBase.s.sol";

/// @title DeployBaseTest — Validate the mainnet bonding curve
contract DeployBaseTest is Test {
    DeployBase deploy;

    function setUp() public {
        deploy = new DeployBase();
    }

    function test_curveLength() public view {
        (uint128[] memory ranges, uint128[] memory prices) = deploy.generateCurve();
        assertEq(ranges.length, 500);
        assertEq(prices.length, 500);
    }

    function test_curveSupplyUniform() public view {
        (uint128[] memory ranges,) = deploy.generateCurve();

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
        (, uint128[] memory prices) = deploy.generateCurve();
        // Step 0 = 0.001 PL_TEST
        assertEq(prices[0], 1e15);
    }

    function test_curveFinalPrice() public view {
        (, uint128[] memory prices) = deploy.generateCurve();
        // Step 499 snapped to exact 1.8882421 PL_TEST
        assertEq(prices[499], 1_888_242_100_000_000_000);
    }

    function test_curveMonotonicallyIncreasing() public view {
        (, uint128[] memory prices) = deploy.generateCurve();
        for (uint256 i = 1; i < 500; i++) {
            assertTrue(prices[i] >= prices[i - 1], "Price must be monotonically increasing");
        }
    }

    function test_curvePenultimatePriceCloseToFinal() public view {
        (, uint128[] memory prices) = deploy.generateCurve();
        // Step 498 should be within 2% of the snapped final price
        // This validates the growth rate approximation hasn't drifted significantly
        uint256 penultimate = prices[498];
        uint256 final_ = prices[499];
        uint256 ratio = (penultimate * 1e18) / final_;
        // Expected ratio ≈ 1/1.015231 ≈ 0.985 → at least 0.97
        assertTrue(ratio > 0.97e18, "Penultimate price too far from final");
        assertTrue(ratio < 1e18, "Penultimate price should be less than final");
    }

    function test_curveMidpointInRange() public view {
        (, uint128[] memory prices) = deploy.generateCurve();
        // Step 250 (midpoint) should be between initial and final
        assertTrue(prices[250] > prices[0], "Midpoint should exceed initial");
        assertTrue(prices[250] < prices[499], "Midpoint should be below final");
        // Exponential midpoint: 0.001 * 1888.2421^(250/499) ≈ 0.0434
        // Allow 10% tolerance: 0.039 to 0.048
        assertTrue(prices[250] > 0.039e18, "Midpoint price too low");
        assertTrue(prices[250] < 0.048e18, "Midpoint price too high");
    }

    function test_curveNoPriceIsZero() public view {
        (, uint128[] memory prices) = deploy.generateCurve();
        for (uint256 i = 0; i < 500; i++) {
            assertTrue(prices[i] > 0, "Price must be non-zero");
        }
    }
}
