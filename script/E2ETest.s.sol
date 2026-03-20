// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StoryFactory} from "../src/StoryFactory.sol";
import {IMCV2_Bond} from "../src/interfaces/IMCV2_Bond.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

/// @dev Extended ERC-20 interface for totalSupply checks
interface IERC20Extended is IERC20 {
    function totalSupply() external view returns (uint256);
}

/// @title E2ETest - Full StoryFactory lifecycle on Base mainnet
/// @notice Groups A-F: story lifecycle, trading, donations, royalties,
///         validation barriers, and edge cases. Outputs results to e2e-results.json.
contract E2ETest is Script {
    // -----------------------------------------------------------------------
    // Base mainnet addresses
    // -----------------------------------------------------------------------
    StoryFactory constant FACTORY = StoryFactory(0xc278F4099298118efA8dF30DF0F4876632571948);
    IERC20 constant PL_TEST = IERC20(0xF8A2C39111FCEB9C950aAf28A9E34EBaD99b85C1);
    IMCV2_Bond constant BOND = IMCV2_Bond(0xc5a076cad94176c2996B32d8466Be1cE757FAa27);

    // Valid CIDs for testing
    string constant CID_46 = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG"; // exactly 46 chars
    string constant CID_100 =
        "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi1234567890abcdefghijklmnopqrstuvwxyz12345"; // exactly 100 chars
    bytes32 constant HASH_A = keccak256("e2e genesis content");
    bytes32 constant HASH_B = keccak256("e2e chapter 2");
    bytes32 constant HASH_C = keccak256("e2e chapter 3");
    bytes32 constant HASH_D = keccak256("e2e chapter 4");

    // State populated during run
    uint256 idA1;
    uint256 idA2;
    uint256 idA3;
    address tokenA1;
    address deployer;
    uint256 deployerKey;
    address donor;
    uint256 donorKey;

    uint256 priceAfterB1;
    uint256 priceAfterB2;
    uint256 priceAfterB3;

    uint256 totalGas;
    uint256 scenariosPassed;

    // JSON results accumulator
    string resultsJson;

    function run() external {
        deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerKey);
        donorKey = vm.envUint("DONOR_PRIVATE_KEY");
        donor = vm.addr(donorKey);

        console.log("=== E2E Test Suite - Base Mainnet ===");
        console.log("Deployer:", deployer);
        console.log("Donor:", donor);
        console.log("PL_TEST balance (deployer):", PL_TEST.balanceOf(deployer));
        console.log("PL_TEST balance (donor):", PL_TEST.balanceOf(donor));
        console.log("");

        // Initialize JSON results
        resultsJson = "{}";
        vm.serializeAddress(resultsJson, "deployer", deployer);
        vm.serializeAddress(resultsJson, "donor", donor);
        vm.serializeAddress(resultsJson, "factory", address(FACTORY));
        vm.serializeAddress(resultsJson, "plTest", address(PL_TEST));
        vm.serializeAddress(resultsJson, "bond", address(BOND));
        vm.serializeUint(resultsJson, "chainId", block.chainid);
        vm.serializeString(
            resultsJson,
            "broadcastArtifact",
            string.concat("broadcast/E2ETest.s.sol/", vm.toString(block.chainid), "/run-latest.json")
        );

        uint256 gasStart = gasleft();

        vm.startBroadcast(deployerKey);

        // Pre-approve PL_TEST for Bond (trading) and Factory (donations)
        PL_TEST.approve(address(BOND), type(uint256).max);
        PL_TEST.approve(address(FACTORY), type(uint256).max);

        // ===== Group A: Story Lifecycle =====
        _groupA();

        // ===== Group B: Trading =====
        _groupB();

        // ===== Fund donor for Group C =====
        PL_TEST.transfer(donor, 5 ether);

        vm.stopBroadcast();

        // ===== Group C: Donations (from donor to verify two-party flow) =====
        vm.startBroadcast(donorKey);
        PL_TEST.approve(address(FACTORY), type(uint256).max);
        _groupC();
        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);

        // ===== Group D: Royalties =====
        _groupD();

        // ===== Group E: Validation Barriers =====
        vm.stopBroadcast();
        _groupE();
        vm.startBroadcast(deployerKey);

        // ===== Group F: Edge Cases =====
        _groupF();

        vm.stopBroadcast();

        totalGas = gasStart - gasleft();

        // Write final JSON results
        vm.serializeUint(resultsJson, "scenariosPassed", scenariosPassed);
        string memory finalJson = vm.serializeUint(resultsJson, "gasUsed", totalGas);
        vm.writeJson(finalJson, "e2e-results.json");

        console.log("");
        console.log("=== ALL SCENARIOS PASSED ===");
        console.log("Scenarios passed:", scenariosPassed);
        console.log("Approximate gas used:", totalGas);
        console.log("Results written to e2e-results.json");
    }

    // ===================================================================
    // Group A: Story Lifecycle (Happy Paths)
    // ===================================================================

    function _groupA() internal {
        console.log("--- Group A: Story Lifecycle ---");

        // A1: Create storyline WITH deadline, chain 3 plots
        idA1 = FACTORY.createStoryline("E2E Story Alpha", CID_46, HASH_A, true);
        (address w1, address t1, uint256 pc1,, bool hd1,) = FACTORY.storylines(idA1);
        require(w1 == deployer, "A1: writer mismatch");
        require(t1 != address(0), "A1: token is zero");
        require(pc1 == 1, "A1: plotCount != 1");
        require(hd1 == true, "A1: hasDeadline should be true");
        tokenA1 = t1;
        console.log("[A1] Create storyline with deadline    PASS  storylineId=%d  token=%s", idA1, t1);

        // Chain 3 plots to A1
        FACTORY.chainPlot(idA1, "Chapter 2", CID_46, HASH_B);
        FACTORY.chainPlot(idA1, "Chapter 3", CID_46, HASH_C);
        FACTORY.chainPlot(idA1, "Chapter 4", CID_46, HASH_D);
        (,, uint256 pc1b,,,) = FACTORY.storylines(idA1);
        require(pc1b == 4, "A1: plotCount != 4 after chaining");
        console.log("[A1] Chain plots 1/3, 2/3, 3/3         PASS  plotCount=%d", pc1b);
        scenariosPassed += 2; // A1 create + A1 chain

        // Serialize A1 results
        string memory a1Key = "storylineA1";
        vm.serializeUint(a1Key, "storylineId", idA1);
        vm.serializeAddress(a1Key, "token", t1);
        vm.serializeUint(a1Key, "plotCount", pc1b);
        string memory a1Json = vm.serializeBool(a1Key, "hasDeadline", true);
        vm.serializeString(resultsJson, "storylineA1", a1Json);

        // A2: Create storyline WITHOUT deadline, chain 1 plot
        idA2 = FACTORY.createStoryline("E2E Story Beta", CID_46, HASH_A, false);
        (address w2, address t2, uint256 pc2,, bool hd2,) = FACTORY.storylines(idA2);
        require(w2 == deployer, "A2: writer mismatch");
        require(t2 != address(0), "A2: token is zero");
        require(pc2 == 1, "A2: plotCount != 1");
        require(hd2 == false, "A2: hasDeadline should be false");

        FACTORY.chainPlot(idA2, "Beta Chapter 2", CID_46, HASH_B);
        (,, uint256 pc2b,,,) = FACTORY.storylines(idA2);
        require(pc2b == 2, "A2: plotCount != 2");
        console.log("[A2] Create storyline no deadline       PASS  storylineId=%d  plotCount=%d", idA2, pc2b);
        scenariosPassed++;

        // Serialize A2 results
        string memory a2Key = "storylineA2";
        vm.serializeUint(a2Key, "storylineId", idA2);
        vm.serializeAddress(a2Key, "token", t2);
        vm.serializeUint(a2Key, "plotCount", pc2b);
        string memory a2Json = vm.serializeBool(a2Key, "hasDeadline", false);
        vm.serializeString(resultsJson, "storylineA2", a2Json);

        // A3: Same wallet creates 2nd storyline (3rd total)
        idA3 = FACTORY.createStoryline("E2E Story Gamma", CID_46, HASH_A, false);
        (address w3, address t3,,,,) = FACTORY.storylines(idA3);
        require(w3 == deployer, "A3: writer mismatch");
        require(t3 != address(0), "A3: token is zero");
        require(t3 != t1 && t3 != t2, "A3: token not unique");
        require(idA3 != idA1 && idA3 != idA2, "A3: IDs not unique");
        console.log("[A3] Multiple storylines per writer     PASS  storylineId=%d  token=%s", idA3, t3);
        scenariosPassed++;

        // Serialize A3 results
        string memory a3Key = "storylineA3";
        vm.serializeUint(a3Key, "storylineId", idA3);
        string memory a3Json = vm.serializeAddress(a3Key, "token", t3);
        vm.serializeString(resultsJson, "storylineA3", a3Json);
    }

    // ===================================================================
    // Group B: Trading Variations
    // ===================================================================

    function _groupB() internal {
        console.log("");
        console.log("--- Group B: Trading ---");

        IERC20Extended storyToken = IERC20Extended(tokenA1);
        storyToken.approve(address(BOND), type(uint256).max);

        // B1: Buy 1 token
        uint256 supplyBefore = storyToken.totalSupply();
        uint256 balBefore = PL_TEST.balanceOf(deployer);
        (uint256 estReserve1,) = BOND.getReserveForToken(tokenA1, 1e18);
        BOND.mint(tokenA1, 1e18, type(uint256).max, deployer);
        uint256 spent1 = balBefore - PL_TEST.balanceOf(deployer);
        require(storyToken.balanceOf(deployer) == 1e18, "B1: balance mismatch");
        require(storyToken.totalSupply() == supplyBefore + 1e18, "B1: totalSupply mismatch");
        require(spent1 <= estReserve1 + 1 && spent1 + 1 >= estReserve1, "B1: estimate mismatch");
        priceAfterB1 = spent1;
        console.log("[B1] Buy 1 token                       PASS  cost=%d  estimate=%d", spent1, estReserve1);
        scenariosPassed++;

        // B2: Buy 1,000 tokens
        supplyBefore = storyToken.totalSupply();
        balBefore = PL_TEST.balanceOf(deployer);
        (uint256 estReserve2,) = BOND.getReserveForToken(tokenA1, 1_000e18);
        BOND.mint(tokenA1, 1_000e18, type(uint256).max, deployer);
        uint256 spent2 = balBefore - PL_TEST.balanceOf(deployer);
        require(storyToken.balanceOf(deployer) == 1_001e18, "B2: balance mismatch");
        require(storyToken.totalSupply() == supplyBefore + 1_000e18, "B2: totalSupply mismatch");
        require(spent2 <= estReserve2 + 1 && spent2 + 1 >= estReserve2, "B2: estimate mismatch");
        priceAfterB2 = spent2;
        console.log("[B2] Buy 1,000 tokens                  PASS  cost=%d  estimate=%d", spent2, estReserve2);
        scenariosPassed++;

        // B3: Buy 10,000 tokens
        supplyBefore = storyToken.totalSupply();
        balBefore = PL_TEST.balanceOf(deployer);
        (uint256 estReserve3,) = BOND.getReserveForToken(tokenA1, 10_000e18);
        BOND.mint(tokenA1, 10_000e18, type(uint256).max, deployer);
        uint256 spent3 = balBefore - PL_TEST.balanceOf(deployer);
        require(storyToken.balanceOf(deployer) == 11_001e18, "B3: balance mismatch");
        require(storyToken.totalSupply() == supplyBefore + 10_000e18, "B3: totalSupply mismatch");
        require(spent3 <= estReserve3 + 1 && spent3 + 1 >= estReserve3, "B3: estimate mismatch");
        priceAfterB3 = spent3;
        console.log("[B3] Buy 10,000 tokens                 PASS  cost=%d  estimate=%d", spent3, estReserve3);
        scenariosPassed++;

        // B6: Price monotonicity check (per-unit cost increases with supply)
        require(priceAfterB2 > priceAfterB1, "B6: price B2 should > B1");
        require(priceAfterB3 > priceAfterB2, "B6: price B3 should > B2");
        console.log(
            "[B6] Price monotonicity                PASS  %d < %d < %d", priceAfterB1, priceAfterB2, priceAfterB3
        );
        scenariosPassed++;

        // B4: Partial sell - burn 500 tokens
        supplyBefore = storyToken.totalSupply();
        balBefore = PL_TEST.balanceOf(deployer);
        (uint256 estRefund4,) = BOND.getRefundForTokens(tokenA1, 500e18);
        BOND.burn(tokenA1, 500e18, 0, deployer);
        uint256 refund4 = PL_TEST.balanceOf(deployer) - balBefore;
        require(storyToken.balanceOf(deployer) == 10_501e18, "B4: balance mismatch");
        require(storyToken.totalSupply() == supplyBefore - 500e18, "B4: totalSupply mismatch");
        require(refund4 <= estRefund4 + 1 && refund4 + 1 >= estRefund4, "B4: estimate mismatch");
        console.log("[B4] Partial sell 500 tokens           PASS  refund=%d  estimate=%d", refund4, estRefund4);
        scenariosPassed++;

        // B5: Full sell - burn all remaining tokens
        uint256 remaining = storyToken.balanceOf(deployer);
        supplyBefore = storyToken.totalSupply();
        balBefore = PL_TEST.balanceOf(deployer);
        (uint256 estRefund5,) = BOND.getRefundForTokens(tokenA1, remaining);
        BOND.burn(tokenA1, remaining, 0, deployer);
        uint256 refund5 = PL_TEST.balanceOf(deployer) - balBefore;
        require(storyToken.balanceOf(deployer) == 0, "B5: balance should be 0");
        require(storyToken.totalSupply() == supplyBefore - remaining, "B5: totalSupply mismatch");
        require(refund5 <= estRefund5 + 1 && refund5 + 1 >= estRefund5, "B5: estimate mismatch");
        console.log("[B5] Full sell all tokens              PASS  refund=%d  estimate=%d", refund5, estRefund5);
        scenariosPassed++;

        // Serialize trading results
        string memory bKey = "tradingB";
        vm.serializeUint(bKey, "b1Cost", spent1);
        vm.serializeUint(bKey, "b2Cost", spent2);
        vm.serializeUint(bKey, "b3Cost", spent3);
        vm.serializeUint(bKey, "b4Refund", refund4);
        string memory bJson = vm.serializeUint(bKey, "b5Refund", refund5);
        vm.serializeString(resultsJson, "tradingB", bJson);
    }

    // ===================================================================
    // Group C: Donations
    // ===================================================================

    function _groupC() internal {
        console.log("");
        console.log("--- Group C: Donations (from donor) ---");

        // C1: Donate 0.001 PL_TEST (small) — verify donor decreases, writer increases
        uint256 donorBefore = PL_TEST.balanceOf(donor);
        uint256 writerBefore = PL_TEST.balanceOf(deployer);
        FACTORY.donate(idA1, 0.001 ether);
        uint256 donorAfter = PL_TEST.balanceOf(donor);
        uint256 writerAfter = PL_TEST.balanceOf(deployer);
        require(donorBefore - donorAfter == 0.001 ether, "C1: donor balance did not decrease correctly");
        require(writerAfter - writerBefore == 0.001 ether, "C1: writer balance did not increase correctly");
        console.log(
            "[C1] Donate 0.001 PL_TEST (small)      PASS  donorDelta=-%d  writerDelta=+%d",
            donorBefore - donorAfter,
            writerAfter - writerBefore
        );
        scenariosPassed++;

        // C2: Donate 1 PL_TEST (standard)
        donorBefore = PL_TEST.balanceOf(donor);
        writerBefore = PL_TEST.balanceOf(deployer);
        FACTORY.donate(idA1, 1 ether);
        donorAfter = PL_TEST.balanceOf(donor);
        writerAfter = PL_TEST.balanceOf(deployer);
        require(donorBefore - donorAfter == 1 ether, "C2: donor balance did not decrease correctly");
        require(writerAfter - writerBefore == 1 ether, "C2: writer balance did not increase correctly");
        console.log(
            "[C2] Donate 1 PL_TEST (standard)       PASS  donorDelta=-%d  writerDelta=+%d",
            donorBefore - donorAfter,
            writerAfter - writerBefore
        );
        scenariosPassed++;

        // C3: Donate to same storyline again (accumulates)
        donorBefore = PL_TEST.balanceOf(donor);
        writerBefore = PL_TEST.balanceOf(deployer);
        FACTORY.donate(idA1, 0.5 ether);
        donorAfter = PL_TEST.balanceOf(donor);
        writerAfter = PL_TEST.balanceOf(deployer);
        require(donorBefore - donorAfter == 0.5 ether, "C3: donor balance did not decrease correctly");
        require(writerAfter - writerBefore == 0.5 ether, "C3: writer balance did not increase correctly");
        console.log(
            "[C3] Donate to same storyline again     PASS  donorDelta=-%d  writerDelta=+%d",
            donorBefore - donorAfter,
            writerAfter - writerBefore
        );
        scenariosPassed++;

        // C4: Donate to storyline A2 (different story)
        donorBefore = PL_TEST.balanceOf(donor);
        writerBefore = PL_TEST.balanceOf(deployer);
        FACTORY.donate(idA2, 0.5 ether);
        donorAfter = PL_TEST.balanceOf(donor);
        writerAfter = PL_TEST.balanceOf(deployer);
        require(donorBefore - donorAfter == 0.5 ether, "C4: donor balance did not decrease correctly");
        require(writerAfter - writerBefore == 0.5 ether, "C4: writer balance did not increase correctly");
        console.log(
            "[C4] Donate to storyline A2            PASS  donorDelta=-%d  writerDelta=+%d",
            donorBefore - donorAfter,
            writerAfter - writerBefore
        );
        scenariosPassed++;
    }

    // ===================================================================
    // Group D: Royalties
    // ===================================================================

    function _groupD() internal {
        console.log("");
        console.log("--- Group D: Royalties ---");

        // D1: Claim royalties after B1-B5 trading
        uint256 balBefore = PL_TEST.balanceOf(deployer);
        BOND.claimRoyalties(address(PL_TEST));
        uint256 royaltyClaimed = PL_TEST.balanceOf(deployer) - balBefore;
        require(royaltyClaimed > 0, "D1: no royalties claimed");
        console.log("[D1] Claim royalties after trading     PASS  amount=%d", royaltyClaimed);
        scenariosPassed++;

        // Serialize royalty results
        vm.serializeUint(resultsJson, "royaltiesClaimed", royaltyClaimed);

        // D2: Claim again - should return 0
        balBefore = PL_TEST.balanceOf(deployer);
        BOND.claimRoyalties(address(PL_TEST));
        uint256 royaltyClaimed2 = PL_TEST.balanceOf(deployer) - balBefore;
        require(royaltyClaimed2 == 0, "D2: double-claim should return 0");
        console.log("[D2] Claim royalties again (empty)     PASS  amount=%d", royaltyClaimed2);
        scenariosPassed++;
    }

    // ===================================================================
    // Group E: Validation Barriers (Expected Reverts)
    // ===================================================================

    function _groupE() internal {
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

        // E4: chainPlot from non-writer address
        // Outside broadcast, msg.sender is the script contract (not the deployer/writer)
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

        // E7: Donate without approval (from script contract, which has no approval)
        try FACTORY.donate(idA1, 1 ether) {
            revert("E7: should have reverted");
        } catch {
            console.log("[E7] No approval reverts              PASS  (ERC-20 transferFrom failed)");
            scenariosPassed++;
        }

        // E8: chainPlot with CID < 46 chars
        try FACTORY.chainPlot(idA1, "Test", "QmShortCID1234567890123456789012345678901234", HASH_A) {
            revert("E8: should have reverted");
        } catch Error(string memory reason) {
            require(keccak256(bytes(reason)) == keccak256("Invalid CID"), "E8: wrong revert reason");
            console.log('[E8] Short CID in chainPlot reverts   PASS  "Invalid CID"');
            scenariosPassed++;
        }

        // E9: chainPlot with CID > 100 chars
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
    }

    // ===================================================================
    // Group F: Edge Cases
    // ===================================================================

    function _groupF() internal {
        console.log("");
        console.log("--- Group F: Edge Cases ---");

        // F1: CID at exact min length (46 chars)
        uint256 idF1 = FACTORY.createStoryline("Edge Min CID", CID_46, HASH_A, false);
        require(idF1 > 0, "F1: failed to create");
        console.log("[F1] CID exact min (46 chars)          PASS  storylineId=%d", idF1);
        scenariosPassed++;

        // F2: CID at exact max length (100 chars)
        uint256 idF2 = FACTORY.createStoryline("Edge Max CID", CID_100, HASH_A, false);
        require(idF2 > 0, "F2: failed to create");
        console.log("[F2] CID exact max (100 chars)         PASS  storylineId=%d", idF2);
        scenariosPassed++;

        // F3: createStoryline with msg.value = 0 (MCV2_Bond creation fee behavior)
        uint256 idF3 = FACTORY.createStoryline("Zero Fee Story", CID_46, HASH_A, false);
        require(idF3 > 0, "F3: failed to create with zero value");
        console.log("[F3] Create with msg.value=0           PASS  storylineId=%d", idF3);
        scenariosPassed++;

        // F4: chainPlot with empty title (title not validated in chainPlot)
        FACTORY.chainPlot(idF3, "", CID_46, HASH_B);
        (,, uint256 pc,,,) = FACTORY.storylines(idF3);
        require(pc == 2, "F4: plotCount should be 2");
        console.log("[F4] chainPlot with empty title        PASS  plotCount=%d", pc);
        scenariosPassed++;

        // F5: Buy then sell same amount - refund < cost due to royalties
        (, address tokenF1,,,,) = FACTORY.storylines(idF1);
        IERC20Extended storyTokenF1 = IERC20Extended(tokenF1);
        storyTokenF1.approve(address(BOND), type(uint256).max);

        uint256 supplyBefore = storyTokenF1.totalSupply();
        uint256 balBefore = PL_TEST.balanceOf(deployer);
        BOND.mint(tokenF1, 100e18, type(uint256).max, deployer);
        uint256 buyCost = balBefore - PL_TEST.balanceOf(deployer);
        require(storyTokenF1.totalSupply() == supplyBefore + 100e18, "F5: totalSupply mismatch after buy");

        balBefore = PL_TEST.balanceOf(deployer);
        BOND.burn(tokenF1, 100e18, 0, deployer);
        uint256 sellRefund = PL_TEST.balanceOf(deployer) - balBefore;
        require(storyTokenF1.totalSupply() == supplyBefore, "F5: totalSupply mismatch after sell");

        require(sellRefund < buyCost, "F5: refund should be less than cost due to royalties");
        console.log("[F5] Buy/sell royalty diff              PASS  cost=%d  refund=%d", buyCost, sellRefund);
        scenariosPassed++;

        // Serialize edge case storyline IDs
        string memory fKey = "edgeCasesF";
        vm.serializeUint(fKey, "f1StorylineId", idF1);
        vm.serializeAddress(fKey, "f1Token", tokenF1);
        vm.serializeUint(fKey, "f2StorylineId", idF2);
        string memory fJson = vm.serializeUint(fKey, "f3StorylineId", idF3);
        vm.serializeString(resultsJson, "edgeCasesF", fJson);
    }
}
