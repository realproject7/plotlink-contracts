// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StoryFactory} from "../src/StoryFactory.sol";
import {IMCV2_Bond} from "../src/interfaces/IMCV2_Bond.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @title E2ETestReverts - Revert-validation tests (simulation only, no broadcast)
/// @notice Groups D2, E1-E9, F3: expected-revert scenarios that cannot run
///         under --broadcast. Run with `forge script` (no --broadcast flag).
///         Requires the main E2ETest to have run first (needs existing storylines).
contract E2ETestReverts is Script {
    StoryFactory constant FACTORY = StoryFactory(0x27B4FCf333f29a3865b3B76ea00C955D7b64BD0F);
    IERC20 constant PL_TEST = IERC20(0xF8A2C39111FCEB9C950aAf28A9E34EBaD99b85C1);
    IMCV2_Bond constant BOND = IMCV2_Bond(0xc5a076cad94176c2996B32d8466Be1cE757FAa27);

    string constant CID_46 = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG";
    bytes32 constant HASH_A = keccak256("e2e genesis content");

    uint256 scenariosPassed;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Read storyline IDs from e2e-results.json (produced by E2ETest)
        string memory json = vm.readFile("e2e-results.json");
        uint256 idA1 = vm.parseJsonUint(json, ".storylineA1.storylineId");

        console.log("=== E2E Revert Tests (Simulation Only) ===");
        console.log("Deployer:", deployer);
        console.log("Using storylineId:", idA1);
        console.log("");

        // ===== Group D2: Empty royalty claim =====
        console.log("--- Group D: Royalties (reverts) ---");

        // Drain any pending royalties first (F5 buy/sell may have generated new ones)
        vm.prank(deployer);
        try BOND.claimRoyalties(address(PL_TEST)) {} catch {}

        // Now the second claim should revert with NothingToClaim
        vm.prank(deployer);
        try BOND.claimRoyalties(address(PL_TEST)) {
            revert("D2: should have reverted on empty claim");
        } catch {
            console.log("[D2] Empty claim reverts               PASS  (MCV2_Royalty__NothingToClaim)");
            scenariosPassed++;
        }

        // ===== Group E: Validation Barriers =====
        console.log("");
        console.log("--- Group E: Validation Barriers ---");

        // E1: Empty title
        try FACTORY.createStoryline("", CID_46, HASH_A, false) {
            revert("E1: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Empty title"), "E1: wrong revert reason");
            console.log('[E1] Empty title reverts               PASS  "Empty title"');
            scenariosPassed++;
        }

        // E2: CID too short (2 chars)
        try FACTORY.createStoryline("Test", "Qm", HASH_A, false) {
            revert("E2: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Invalid CID"), "E2: wrong revert reason");
            console.log('[E2] Short CID reverts                PASS  "Invalid CID"');
            scenariosPassed++;
        }

        // E3: CID too long (101 chars)
        try FACTORY.createStoryline(
            "Test",
            "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi1234567890abcdefghijklmnopqrstuvwxyz12345X",
            HASH_A,
            false
        ) {
            revert("E3: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Invalid CID"), "E3: wrong revert reason");
            console.log('[E3] Long CID reverts                 PASS  "Invalid CID"');
            scenariosPassed++;
        }

        // E4: chainPlot from non-writer address (script contract is not the writer)
        try FACTORY.chainPlot(idA1, "Unauthorized", CID_46, HASH_A) {
            revert("E4: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Not writer"), "E4: wrong revert reason");
            console.log('[E4] Non-writer chainPlot reverts     PASS  "Not writer"');
            scenariosPassed++;
        }

        // E5: Zero donation
        try FACTORY.donate(idA1, 0) {
            revert("E5: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Zero amount"), "E5: wrong revert reason");
            console.log('[E5] Zero donation reverts            PASS  "Zero amount"');
            scenariosPassed++;
        }

        // E6: Donate to non-existent storyline
        try FACTORY.donate(999999, 1) {
            revert("E6: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Storyline does not exist"), "E6: wrong revert reason");
            console.log('[E6] Non-existent storyline reverts   PASS  "Storyline does not exist"');
            scenariosPassed++;
        }

        // E7: Donate without approval (script contract has no approval)
        try FACTORY.donate(idA1, 1 ether) {
            revert("E7: should have reverted");
        } catch {
            console.log("[E7] No approval reverts              PASS  (ERC-20 transferFrom failed)");
            scenariosPassed++;
        }

        // E8: chainPlot with CID < 46 chars (prank as deployer to pass writer check)
        vm.prank(deployer);
        try FACTORY.chainPlot(idA1, "Test", "QmShortCID1234567890123456789012345678901234", HASH_A) {
            revert("E8: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Invalid CID"), "E8: wrong revert reason");
            console.log('[E8] Short CID in chainPlot reverts   PASS  "Invalid CID"');
            scenariosPassed++;
        }

        // E9: chainPlot with CID > 100 chars (prank as deployer to pass writer check)
        vm.prank(deployer);
        try FACTORY.chainPlot(
            idA1,
            "Test",
            "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi1234567890abcdefghijklmnopqrstuvwxyz12345X",
            HASH_A
        ) {
            revert("E9: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Invalid CID"), "E9: wrong revert reason");
            console.log('[E9] Long CID in chainPlot reverts    PASS  "Invalid CID"');
            scenariosPassed++;
        }

        // E10: chainPlot with empty title (new validation from #42)
        vm.prank(deployer);
        try FACTORY.chainPlot(idA1, "", CID_46, HASH_A) {
            revert("E10: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Empty title"), "E10: wrong revert reason");
            console.log('[E10] Empty title in chainPlot reverts PASS  "Empty title"');
            scenariosPassed++;
        }

        // E11: createStoryline with zero hash
        try FACTORY.createStoryline("Test", CID_46, bytes32(0), false) {
            revert("E11: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Empty hash"), "E11: wrong revert reason");
            console.log('[E11] Zero hash in create reverts      PASS  "Empty hash"');
            scenariosPassed++;
        }

        // E12: chainPlot with zero hash
        vm.prank(deployer);
        try FACTORY.chainPlot(idA1, "Test", CID_46, bytes32(0)) {
            revert("E12: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Empty hash"), "E12: wrong revert reason");
            console.log('[E12] Zero hash in chainPlot reverts   PASS  "Empty hash"');
            scenariosPassed++;
        }

        // E13: updateCurve by non-owner
        try FACTORY.updateCurve(new uint128[](1), new uint128[](1)) {
            revert("E13: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Not owner"), "E13: wrong revert reason");
            console.log('[E13] Non-owner updateCurve reverts    PASS  "Not owner"');
            scenariosPassed++;
        }

        // ===== F3: Zero creation fee =====
        console.log("");
        console.log("--- Group F: Edge Cases (reverts) ---");

        try FACTORY.createStoryline("Zero Fee Story", CID_46, HASH_A, false) {
            revert("F3: should have reverted without creation fee");
        } catch {
            console.log("[F3] Zero fee reverts                  PASS  (MCV2_Bond__InvalidCreationFee)");
            scenariosPassed++;
        }

        // ===== Group G: hasSunset view =====
        console.log("");
        console.log("--- Group G: hasSunset ---");

        // G1: hasSunset on active storyline (no deadline) — should be false
        bool sunset1 = FACTORY.hasSunset(idA1);
        require(!sunset1, "G1: hasSunset should be false for no-deadline storyline");
        console.log("[G1] hasSunset (no deadline) = false   PASS");
        scenariosPassed++;

        // G2: hasSunset on expired deadline storyline
        // Read storylineA2 which has hasDeadline from e2e-results.json
        uint256 idA2 = vm.parseJsonUint(json, ".storylineA2.storylineId");
        bool a2HasDeadline = vm.parseJsonBool(json, ".storylineA2.hasDeadline");
        if (!a2HasDeadline) {
            // A2 has no deadline — hasSunset should be false even after warp
            vm.warp(block.timestamp + 365 days);
            bool sunset2 = FACTORY.hasSunset(idA2);
            require(!sunset2, "G2: hasSunset should be false without deadline even after warp");
            console.log("[G2] hasSunset (no deadline, warped)    PASS");
        } else {
            // A2 has deadline — warp past it
            vm.warp(block.timestamp + 169 hours);
            bool sunset2 = FACTORY.hasSunset(idA2);
            require(sunset2, "G2: hasSunset should be true after deadline");
            console.log("[G2] hasSunset (expired deadline)       PASS");
        }
        scenariosPassed++;

        // ===== Group H: Constructor validations (simulation only) =====
        console.log("");
        console.log("--- Group H: Constructor validations ---");

        uint128[] memory r1 = new uint128[](1);
        r1[0] = 1e18;
        uint128[] memory p1 = new uint128[](1);
        p1[0] = 1e15;

        // H1: Zero bond address
        try new StoryFactory(address(0), address(1), 1e18, r1, p1) {
            revert("H1: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Zero bond address"), "H1: wrong revert reason");
            console.log('[H1] Zero bond address reverts         PASS  "Zero bond address"');
            scenariosPassed++;
        }

        // H2: Zero token address
        try new StoryFactory(address(1), address(0), 1e18, r1, p1) {
            revert("H2: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Zero token address"), "H2: wrong revert reason");
            console.log('[H2] Zero token address reverts        PASS  "Zero token address"');
            scenariosPassed++;
        }

        // H3: Too many steps (>1000)
        uint128[] memory bigR = new uint128[](1001);
        uint128[] memory bigP = new uint128[](1001);
        for (uint256 i = 0; i < 1001; i++) {
            bigR[i] = uint128(i + 1);
            bigP[i] = uint128(i + 1);
        }
        try new StoryFactory(address(1), address(1), 1e18, bigR, bigP) {
            revert("H3: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Too many steps"), "H3: wrong revert reason");
            console.log('[H3] >1000 steps reverts               PASS  "Too many steps"');
            scenariosPassed++;
        }

        console.log("");
        console.log("=== ALL REVERT TESTS PASSED ===");
        console.log("Scenarios passed:", scenariosPassed);
    }
}
