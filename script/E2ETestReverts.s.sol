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
    StoryFactory constant FACTORY = StoryFactory(0xc278F4099298118efA8dF30DF0F4876632571948);
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

        // ===== F3: Zero creation fee =====
        console.log("");
        console.log("--- Group F: Edge Cases (reverts) ---");

        try FACTORY.createStoryline("Zero Fee Story", CID_46, HASH_A, false) {
            revert("F3: should have reverted without creation fee");
        } catch {
            console.log("[F3] Zero fee reverts                  PASS  (MCV2_Bond__InvalidCreationFee)");
            scenariosPassed++;
        }

        console.log("");
        console.log("=== ALL REVERT TESTS PASSED ===");
        console.log("Scenarios passed:", scenariosPassed);
    }
}
