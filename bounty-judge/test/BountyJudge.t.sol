// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/BountyJudge.sol";
import "../contracts/RitualBountyJudge.sol";

// ─── Mock LLM Precompile ───
// Deployed at 0x0802 to simulate Ritual Chain's LLM inference precompile.
// Returns abi.encode(bytes simmedInput, bytes actualOutput) as expected by _executePrecompile.
contract MockLLMPrecompile {
    bytes public lastInput;

    // Fallback: handles raw precompile.call(input) used by _executePrecompile
    fallback(bytes calldata input) external returns (bytes memory) {
        lastInput = input;
        // Short-running async precompile response format:
        // abi.encode(bytes simmedInput, bytes actualOutput)
        return abi.encode(
            input,  // simmedInput = echo input
            bytes('{"winnerIndex":0,"ranking":[{"index":0,"score":95,"reason":"Best answer"}],"summary":"AI judge review complete"}')  // actualOutput
        );
    }
}

// ─── Mock Ritual Attestation Verifier ───
// Simulates Ritual's on-chain TEE attestation verifier.
// `verifyAttestation` returns the toggled `valid` flag so tests can drive both
// the success path and the "invalid attestation" revert path.
contract MockRitualVerifier {
    bool public valid = true;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function verifyAttestation(
        bytes32, // enclaveCodeHash
        bytes calldata, // input
        bytes calldata, // output
        bytes calldata // attestation
    ) external view returns (bool) {
        return valid;
    }
}

// ═══════════════════════════════════════════════════════
//  BountyJudge Tests
// ═══════════════════════════════════════════════════════
contract BountyJudgeTest is Test {
    BountyJudge public judge;
    MockLLMPrecompile public mockPrecompile;

    address constant OWNER = address(0x1000);
    address constant ALICE = address(0x2000);
    address constant BOB   = address(0x3000);
    address constant CAROL = address(0x4000);

    uint256 public bountyId;
    uint256 constant REWARD = 1 ether;

    bytes32 constant SALT_A = bytes32(uint256(0xaa));
    bytes32 constant SALT_B = bytes32(uint256(0xbb));
    bytes32 constant SALT_C = bytes32(uint256(0xcc));

    function setUp() public {
        // Deploy mock LLM precompile and etch to Ritual precompile address
        mockPrecompile = new MockLLMPrecompile();
        vm.etch(address(0x0802), address(mockPrecompile).code);

        vm.deal(OWNER, 10 ether);

        judge = new BountyJudge(address(0x0802));

        vm.prank(OWNER);
        bountyId = judge.createBounty{value: REWARD}(
            "Best Solidity Pattern",
            "Evaluate correctness, gas efficiency, and code clarity.",
            block.timestamp + 1 days,   // submission deadline
            block.timestamp + 3 days    // reveal deadline
        );
    }

    // Helper: commitment = keccak256(abi.encodePacked(answer, salt, sender, bountyId))
    function makeCommitment(string memory answer, bytes32 salt, address sender)
        internal view returns (bytes32)
    {
        return keccak256(abi.encodePacked(answer, salt, sender, bountyId));
    }

    function commit(address who, string memory answer, bytes32 salt) internal {
        bytes32 c = makeCommitment(answer, salt, who);
        vm.prank(who);
        judge.submitCommitment(bountyId, c);
    }

    function warpToReveal() internal {
        vm.warp(block.timestamp + 2 days); // past submission, within reveal
    }

    function warpPastReveal() internal {
        vm.warp(block.timestamp + 4 days); // past reveal
    }

    // ═══════════════ CREATION ═══════════════

    function testCreateBounty() public {
        (
            address owner,
            string memory title,
            string memory rubric,
            uint256 reward,
            uint256 sd,
            uint256 rd,
            bool judged,
            bool finalized,
            BountyJudge.Phase p
        ) = judge.getBountyCore(bountyId);

        (uint256 pc, uint256 wi,) = judge.getBountyInfo(bountyId);

        assertEq(owner, OWNER);
        assertEq(title, "Best Solidity Pattern");
        assertEq(rubric, "Evaluate correctness, gas efficiency, and code clarity.");
        assertEq(reward, REWARD);
        assertGt(sd, block.timestamp);
        assertGt(rd, sd);
        assertFalse(judged);
        assertFalse(finalized);
        assertEq(pc, 0);
        assertEq(wi, type(uint256).max);
        assertTrue(p == BountyJudge.Phase.SUBMISSION);
    }

    function testCreateBountyNoReward() public {
        vm.prank(OWNER);
        vm.expectRevert("reward required");
        judge.createBounty("title", "rubric", block.timestamp + 1, block.timestamp + 2);
    }

    function testCreateBountyPastSubmissionDeadline() public {
        vm.prank(OWNER);
        vm.expectRevert("submission deadline in past");
        judge.createBounty{value: 1}("t", "r", block.timestamp - 1, block.timestamp + 1);
    }

    function testCreateBountyRevealBeforeSubmission() public {
        vm.prank(OWNER);
        vm.expectRevert("reveal before submission");
        judge.createBounty{value: 1}("t", "r", block.timestamp + 2, block.timestamp + 1);
    }

    // ═══════════════ COMMIT ═══════════════

    function testSubmitCommitment() public {
        commit(ALICE, "answer 1", SALT_A);

        (bytes32 stored,, ) = judge.getSubmission(bountyId, ALICE);
        assertTrue(stored != bytes32(0));
    }

    function testSubmitCommitmentEvent() public {
        bytes32 c = makeCommitment("event test", SALT_A, ALICE);

        vm.prank(ALICE);
        vm.expectEmit(true, true, false, false);
        emit BountyJudge.CommitmentSubmitted(bountyId, ALICE, c);
        judge.submitCommitment(bountyId, c);
    }

    function testDuplicateCommit() public {
        commit(ALICE, "dup", SALT_A);

        vm.prank(ALICE);
        vm.expectRevert("already submitted");
        judge.submitCommitment(bountyId, bytes32(uint256(0x999)));
    }

    function testCommitAfterDeadline() public {
        warpToReveal();

        vm.prank(CAROL);
        vm.expectRevert("submission deadline passed");
        judge.submitCommitment(bountyId, bytes32(uint256(0x1)));
    }

    function testMaxSubmissionsCap() public {
        // Fill up to MAX_SUBMISSIONS (50) — all must succeed.
        for (uint256 i = 0; i < 50; i++) {
            address participant = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            bytes32 c = keccak256(abi.encodePacked("ans", bytes32(i), participant, bountyId));
            vm.prank(participant);
            judge.submitCommitment(bountyId, c);
        }
        assertEq(judge.getParticipants(bountyId).length, 50);

        // 51st must revert.
        address extra = address(0xFFFF);
        vm.prank(extra);
        vm.expectRevert("too many submissions");
        judge.submitCommitment(bountyId, bytes32(uint256(0x1)));
    }

    function testCommitToNonexistentBounty() public {
        vm.prank(ALICE);
        vm.expectRevert(BountyJudge.BountyNotFound.selector);
        judge.submitCommitment(999, bytes32(uint256(0x1)));
    }

    // ═══════════════ REVEAL ═══════════════

    function testRevealCorrect() public {
        commit(ALICE, "the secret", SALT_A);
        warpToReveal();

        vm.prank(ALICE);
        judge.revealAnswer(bountyId, "the secret", SALT_A);

        // Privacy gate: answer hidden until judged (assignment requirement).
        (, string memory answer, bool revealed) = judge.getSubmission(bountyId, ALICE);
        assertEq(answer, "", "answer hidden until judged");
        assertTrue(revealed);
    }

    function testRevealBob() public {
        commit(BOB, "bob answer", SALT_B);
        warpToReveal();

        vm.prank(BOB);
        judge.revealAnswer(bountyId, "bob answer", SALT_B);

        // Privacy gate: answer hidden until judged.
        (, string memory answer, bool revealed) = judge.getSubmission(bountyId, BOB);
        assertEq(answer, "", "answer hidden until judged");
        assertTrue(revealed);
    }

    function testRevealWrongSalt() public {
        commit(ALICE, "secret", SALT_A);
        warpToReveal();

        vm.prank(ALICE);
        vm.expectRevert("invalid commitment");
        judge.revealAnswer(bountyId, "secret", SALT_B);
    }

    function testRevealWrongAnswer() public {
        commit(ALICE, "correct", SALT_A);
        warpToReveal();

        vm.prank(ALICE);
        vm.expectRevert("invalid commitment");
        judge.revealAnswer(bountyId, "wrong", SALT_A);
    }

    function testRevealNoCommit() public {
        warpToReveal();

        vm.prank(ALICE);
        vm.expectRevert("no commitment");
        judge.revealAnswer(bountyId, "no prior", SALT_A);
    }

    function testRevealTwice() public {
        commit(ALICE, "once", SALT_A);
        warpToReveal();

        vm.startPrank(ALICE);
        judge.revealAnswer(bountyId, "once", SALT_A);
        vm.expectRevert("already revealed");
        judge.revealAnswer(bountyId, "once", SALT_A);
        vm.stopPrank();
    }

    function testRevealAfterDeadline() public {
        commit(ALICE, "too late", SALT_A);
        warpPastReveal();

        vm.prank(ALICE);
        vm.expectRevert("reveal deadline passed");
        judge.revealAnswer(bountyId, "too late", SALT_A);
    }

    function testRevealDuringSubmission() public {
        commit(ALICE, "early", SALT_A);
        // still in submission window

        vm.prank(ALICE);
        vm.expectRevert(BountyJudge.StillInSubmission.selector);
        judge.revealAnswer(bountyId, "early", SALT_A);
    }

    function testRevealAnswerTooLong() public {
        // MAX_ANSWER_LENGTH check removed from contract (moved to UI).
        // Commitment for "short" won't match reveal of a 2001-char string -> hash mismatch.
        commit(ALICE, "short", SALT_A);
        warpToReveal();

        string memory longAnswer = new string(2001);
        vm.prank(ALICE);
        vm.expectRevert("invalid commitment");
        judge.revealAnswer(bountyId, longAnswer, SALT_A);
    }

    // ═══════════════ PARTICIPANTS ═══════════════

    function testGetParticipants() public {
        commit(ALICE, "A", SALT_A);
        commit(BOB,   "B", SALT_B);

        address[] memory p = judge.getParticipants(bountyId);
        assertEq(p.length, 2);
        assertEq(p[0], ALICE);
        assertEq(p[1], BOB);
    }

    function testGetRevealedCount() public {
        commit(ALICE, "A", SALT_A);
        commit(BOB,   "B", SALT_B);
        commit(CAROL, "C", SALT_C);
        warpToReveal();

        vm.prank(ALICE); judge.revealAnswer(bountyId, "A", SALT_A);
        vm.prank(BOB);   judge.revealAnswer(bountyId, "B", SALT_B);
        // CAROL does not reveal

        assertEq(judge.getRevealedCount(bountyId), 2);
    }

    // ═══════════════ JUDGE (Ritual LLM Precompile) ═══════════════

    function testJudgeAllSuccess() public {
        commit(ALICE, "A answer", SALT_A);
        commit(BOB,   "B answer", SALT_B);
        warpToReveal();

        vm.prank(ALICE); judge.revealAnswer(bountyId, "A answer", SALT_A);
        vm.prank(BOB);   judge.revealAnswer(bountyId, "B answer", SALT_B);
        warpPastReveal();

        bytes memory llmPrompt = bytes(
            "Rubric: Evaluate code quality.\n\nSubmissions:\n1. A answer\n2. B answer"
        );

        vm.prank(OWNER);
        vm.expectEmit(true, false, false, false);
        emit BountyJudge.AllAnswersJudged(bountyId, bytes(""), bytes32(0), bytes32(0));
        judge.judgeAll(bountyId, llmPrompt);

        (,,,,,, bool judged, bool finalized,) = judge.getBountyCore(bountyId);
        (,, bytes memory aiReview) = judge.getBountyInfo(bountyId);
        assertTrue(judged);
        assertFalse(finalized);
        assertTrue(aiReview.length > 0);
    }

    function testJudgeAllBindsAnswersHashAndInputHash() public {
        commit(ALICE, "A answer", SALT_A);
        commit(BOB,   "B answer", SALT_B);
        warpToReveal();
        vm.prank(ALICE); judge.revealAnswer(bountyId, "A answer", SALT_A);
        vm.prank(BOB);   judge.revealAnswer(bountyId, "B answer", SALT_B);
        warpPastReveal();

        bytes memory llmPrompt = bytes("Rubric + A answer + B answer");
        vm.prank(OWNER);
        judge.judgeAll(bountyId, llmPrompt);

        // Recompute the canonical answers hash the same way the contract does.
        bytes32 expectedAnswers = keccak256(
            abi.encodePacked(
                abi.encode("Evaluate correctness, gas efficiency, and code clarity."),
                ALICE, "A answer",
                BOB,   "B answer"
            )
        );
        (bytes32 answersHash, bytes32 inputHash) = judge.getJudgingAttestation(bountyId);
        assertEq(answersHash, expectedAnswers, "answersHash bound to revealed set");
        assertEq(inputHash, keccak256(llmPrompt), "inputHash bound to submitted prompt");
    }

    function testPrivacyGateHidesAnswerUntilJudged() public {
        commit(ALICE, "A answer", SALT_A);
        commit(BOB,   "B answer", SALT_B);
        warpToReveal();
        vm.prank(ALICE); judge.revealAnswer(bountyId, "A answer", SALT_A);
        vm.prank(BOB);   judge.revealAnswer(bountyId, "B answer", SALT_B);

        // Before judging: getSubmission MUST return "" for the answer (privacy gate).
        (, string memory answerA, bool revealedA) = judge.getSubmission(bountyId, ALICE);
        (, string memory answerB, bool revealedB) = judge.getSubmission(bountyId, BOB);
        assertEq(answerA, "", "answer hidden until judged (Alice)");
        assertEq(answerB, "", "answer hidden until judged (Bob)");
        assertTrue(revealedA);
        assertTrue(revealedB);

        // After judging: answers are visible.
        warpPastReveal();
        vm.prank(OWNER);
        judge.judgeAll(bountyId, bytes("Rubric + answers"));

        (, string memory answerA2, ) = judge.getSubmission(bountyId, ALICE);
        (, string memory answerB2, ) = judge.getSubmission(bountyId, BOB);
        assertEq(answerA2, "A answer", "answer visible after judged");
        assertEq(answerB2, "B answer", "answer visible after judged");
    }

    function testJudgeAllNonOwner() public {
        commit(ALICE, "A", SALT_A);
        warpToReveal();
        vm.prank(ALICE); judge.revealAnswer(bountyId, "A", SALT_A);
        warpPastReveal();

        vm.prank(ALICE);
        vm.expectRevert(BountyJudge.NotOwner.selector);
        judge.judgeAll(bountyId, bytes("prompt"));
    }

    function testJudgeAllBeforeRevealDeadline() public {
        commit(ALICE, "A", SALT_A);
        warpToReveal();
        vm.prank(ALICE); judge.revealAnswer(bountyId, "A", SALT_A);
        // still within reveal window

        vm.prank(OWNER);
        vm.expectRevert("reveal deadline not passed");
        judge.judgeAll(bountyId, bytes("prompt"));
    }

    function testJudgeAllTwice() public {
        commit(ALICE, "A", SALT_A);
        warpToReveal();
        vm.prank(ALICE); judge.revealAnswer(bountyId, "A", SALT_A);
        warpPastReveal();

        vm.startPrank(OWNER);
        judge.judgeAll(bountyId, bytes("first"));

        vm.expectRevert("already judged");
        judge.judgeAll(bountyId, bytes("second"));
        vm.stopPrank();
    }

    function testJudgeAllNoRevealedSubmissions() public {
        commit(ALICE, "A", SALT_A); // committed but never revealed
        commit(BOB,   "B", SALT_B);
        warpPastReveal();

        vm.prank(OWNER);
        vm.expectRevert("no revealed submissions");
        judge.judgeAll(bountyId, bytes("prompt"));
    }

    // ═══════════════ FINALIZE ═══════════════

    function testFinalizeWinner() public {
        commit(ALICE, "winner answer", SALT_A);
        warpToReveal();
        vm.prank(ALICE); judge.revealAnswer(bountyId, "winner answer", SALT_A);
        warpPastReveal();

        vm.prank(OWNER);
        judge.judgeAll(bountyId, bytes("Rubric + Submissions:\n1. winner answer"));

        uint256 balBefore = ALICE.balance;

        vm.prank(OWNER);
        vm.expectEmit(true, true, true, false);
        emit BountyJudge.WinnerFinalized(bountyId, 0, ALICE, REWARD);
        judge.finalizeWinner(bountyId, 0);

        (,,,,,,, bool finalized, BountyJudge.Phase p) = judge.getBountyCore(bountyId);
        (, uint256 wi,) = judge.getBountyInfo(bountyId);
        assertTrue(finalized);
        assertEq(wi, 0);
        assertTrue(p == BountyJudge.Phase.FINALIZED);
        assertEq(ALICE.balance, balBefore + REWARD);
    }

    function testFinalizeNonOwner() public {
        commit(ALICE, "x", SALT_A);
        warpToReveal(); vm.prank(ALICE); judge.revealAnswer(bountyId, "x", SALT_A);
        warpPastReveal();
        vm.prank(OWNER); judge.judgeAll(bountyId, bytes("prompt + answers"));

        vm.prank(ALICE);
        vm.expectRevert(BountyJudge.NotOwner.selector);
        judge.finalizeWinner(bountyId, 0);
    }

    function testFinalizeBeforeJudge() public {
        commit(ALICE, "x", SALT_A);
        warpToReveal(); vm.prank(ALICE); judge.revealAnswer(bountyId, "x", SALT_A);
        // skip judgeAll

        vm.prank(OWNER);
        vm.expectRevert("not judged");
        judge.finalizeWinner(bountyId, 0);
    }

    function testFinalizeUnrevealed() public {
        commit(ALICE, "x", SALT_A); // committed but never revealed
        commit(BOB,   "good", SALT_B);
        warpToReveal();
        vm.prank(BOB); judge.revealAnswer(bountyId, "good", SALT_B);
        warpPastReveal();
        vm.prank(OWNER);
        judge.judgeAll(bountyId, bytes("prompt + BOB's answer"));

        // Try to finalize ALICE (index 0, unrevealed)
        vm.prank(OWNER);
        vm.expectRevert("submission not revealed");
        judge.finalizeWinner(bountyId, 0);
    }

    function testFinalizeTwice() public {
        commit(ALICE, "x", SALT_A);
        warpToReveal(); vm.prank(ALICE); judge.revealAnswer(bountyId, "x", SALT_A);
        warpPastReveal();
        vm.prank(OWNER); judge.judgeAll(bountyId, bytes("prompt + answer"));
        vm.prank(OWNER); judge.finalizeWinner(bountyId, 0);

        vm.prank(OWNER);
        vm.expectRevert("already finalized");
        judge.finalizeWinner(bountyId, 0);
    }

    // ═══════════════ REFUND ═══════════════

    function testRefundWhenNoReveals() public {
        // Participants commit but NOBODY reveals → dead-end, owner reclaims.
        commit(ALICE, "no show", SALT_A);
        commit(BOB,   "no show", SALT_B);
        warpPastReveal();

        assertEq(judge.getRevealedCount(bountyId), 0);
        uint256 ownerBefore = OWNER.balance;

        vm.prank(OWNER);
        judge.refund(bountyId);

        (,,, uint256 rewardAfter,,,,,) = judge.getBountyCore(bountyId);
        assertEq(rewardAfter, 0);
        assertEq(OWNER.balance, ownerBefore + REWARD);
        (,,,,,,, bool finalized,) = judge.getBountyCore(bountyId);
        assertTrue(finalized);
    }

    function testRefundBlockedIfSomeoneRevealed() public {
        // Once a valid reveal exists, refund is NOT allowed (anti-rag) — owner must judge.
        commit(ALICE, "answer", SALT_A);
        warpToReveal();
        vm.prank(ALICE); judge.revealAnswer(bountyId, "answer", SALT_A);
        warpPastReveal();

        vm.prank(OWNER);
        vm.expectRevert(BountyJudge.NotEligibleForRefund.selector);
        judge.refund(bountyId);
    }

    function testRefundBeforeRevealDeadline() public {
        commit(ALICE, "x", SALT_A);
        // still within reveal window
        vm.prank(OWNER);
        vm.expectRevert(BountyJudge.RevealDeadlinePassed.selector);
        judge.refund(bountyId);
    }

    function testRefundNonOwner() public {
        commit(ALICE, "x", SALT_A);
        warpPastReveal();

        vm.prank(ALICE);
        vm.expectRevert(BountyJudge.NotOwner.selector);
        judge.refund(bountyId);
    }

    function testRefundTwice() public {
        commit(ALICE, "x", SALT_A);
        warpPastReveal();
        vm.prank(OWNER); judge.refund(bountyId);

        vm.prank(OWNER);
        vm.expectRevert(BountyJudge.AlreadyFinalized.selector);
        judge.refund(bountyId);
    }

    // ═══════════════ FULL FLOW ═══════════════

    function testFullFlowThreeParticipantsOneInvalidReveal() public {
        commit(ALICE, "answer A", SALT_A);
        commit(BOB,   "answer B", SALT_B);
        commit(CAROL, "answer C", SALT_C);
        warpToReveal();

        // Alice + Bob reveal correctly
        vm.prank(ALICE); judge.revealAnswer(bountyId, "answer A", SALT_A);
        vm.prank(BOB);   judge.revealAnswer(bountyId, "answer B", SALT_B);

        // Carol reveals with WRONG salt → revert
        vm.prank(CAROL);
        vm.expectRevert("invalid commitment");
        judge.revealAnswer(bountyId, "answer C", bytes32(uint256(0xdead)));

        warpPastReveal();

        assertEq(judge.getRevealedCount(bountyId), 2);

        // Owner builds prompt from revealed answers + rubric
        vm.prank(OWNER);
        judge.judgeAll(bountyId, bytes("Rubric: Best code quality.\n\nSubmissions:\n1. answer A\n2. answer B"));

        (,,,,,, bool judged,,) = judge.getBountyCore(bountyId);
        assertTrue(judged);

        // Finalize Alice (index 0)
        uint256 balBefore = ALICE.balance;
        vm.prank(OWNER);
        judge.finalizeWinner(bountyId, 0);

        assertEq(ALICE.balance, balBefore + REWARD);

        (,,,,,,, bool finalized,) = judge.getBountyCore(bountyId);
        assertTrue(finalized);

        // Carol's submission is still unrevealed
        (,, bool carolRevealed) = judge.getSubmission(bountyId, CAROL);
        assertFalse(carolRevealed);
    }

    // ═══════════════ SECURITY ═══════════════

    function testCommitmentBoundToSender() public {
        // Alice commits a hash built for BOB (wrong sender)
        bytes32 fakeCommit = keccak256(abi.encodePacked("secret", SALT_A, BOB, bountyId));

        vm.prank(ALICE);
        judge.submitCommitment(bountyId, fakeCommit);

        warpToReveal();

        // Alice reveals as herself — hash won't match because sender is BOB in commitment
        vm.prank(ALICE);
        vm.expectRevert("invalid commitment");
        judge.revealAnswer(bountyId, "secret", SALT_A);
    }

    function testCommitmentBoundToBountyId() public {
        commit(ALICE, "cross", SALT_A);

        // Create second bounty
        vm.prank(OWNER);
        uint256 bounty2 = judge.createBounty{value: 1 ether}(
            "Second Bounty", "Rubric 2",
            block.timestamp + 1 days,
            block.timestamp + 3 days
        );

        // Alice commits on bounty2 with SAME answer+salt, DIFFERENT bountyId
        bytes32 c2 = keccak256(abi.encodePacked("cross", SALT_A, ALICE, bounty2));
        vm.prank(ALICE);
        judge.submitCommitment(bounty2, c2);

        warpToReveal();

        // Both reveals should pass (different bountyIds in hash)
        vm.prank(ALICE);
        judge.revealAnswer(bountyId, "cross", SALT_A);

        vm.prank(ALICE);
        judge.revealAnswer(bounty2, "cross", SALT_A);

        (,, bool r1) = judge.getSubmission(bountyId, ALICE);
        (,, bool r2) = judge.getSubmission(bounty2, ALICE);
        assertTrue(r1);
        assertTrue(r2);
    }

    function testFinalizeInvalidIndex() public {
        commit(ALICE, "x", SALT_A);
        warpToReveal();
        vm.prank(ALICE); judge.revealAnswer(bountyId, "x", SALT_A);
        warpPastReveal();
        vm.prank(OWNER); judge.judgeAll(bountyId, bytes("prompt + answer"));

        // Only index 0 exists (1 participant). Out-of-range index must revert.
        vm.prank(OWNER);
        vm.expectRevert("invalid index");
        judge.finalizeWinner(bountyId, 1);
    }
}

// ═══════════════════════════════════════════════════════
//  TRACK 2: Ritual TEE Tests
// ═══════════════════════════════════════════════════════
contract RitualBountyJudgeTest is Test {
    RitualBountyJudge public rJudge;
    MockRitualVerifier public verifier;
    bytes32 constant ENCLAVE_HASH = bytes32(uint256(0xdeadbeef));

    address constant CREATOR = address(0x1);
    address constant ALICE   = address(0x2);
    address constant BOB     = address(0x3);

    uint256 public bountyId;

    function setUp() public {
        verifier = new MockRitualVerifier();

        vm.prank(CREATOR);
        rJudge = new RitualBountyJudge();

        vm.prank(CREATOR);
        bountyId = rJudge.createBounty(
            block.timestamp + 1 days,
            ENCLAVE_HASH,
            address(verifier)
        );
    }

    function testCreateBounty() public {
        (address c, uint256 d, uint256 pc, uint256 wi, RitualBountyJudge.Phase p, bytes32 eh)
            = rJudge.getBounty(bountyId);
        assertEq(c, CREATOR);
        assertGt(d, block.timestamp);
        assertEq(pc, 0);
        assertEq(wi, 0);
        assertTrue(p == RitualBountyJudge.Phase.SUBMISSION);
        assertEq(eh, ENCLAVE_HASH);
    }

    function testSubmitEncrypted() public {
        bytes memory enc = hex"deadbeefcafe";
        vm.prank(ALICE);
        rJudge.submitEncryptedAnswer(bountyId, enc);

        (bytes memory stored, bool sub, uint256 sc) =
            rJudge.getSubmissionEncrypted(bountyId, ALICE);
        assertEq(stored, enc);
        assertTrue(sub);
        assertEq(sc, 0);
    }

    function testDuplicateEncrypted() public {
        vm.prank(ALICE);
        rJudge.submitEncryptedAnswer(bountyId, hex"01");

        vm.prank(ALICE);
        vm.expectRevert("already submitted");
        rJudge.submitEncryptedAnswer(bountyId, hex"02");
    }

    function testSubmitAfterDeadline() public {
        vm.warp(block.timestamp + 2 days);
        vm.prank(ALICE);
        vm.expectRevert("deadline passed");
        rJudge.submitEncryptedAnswer(bountyId, bytes("late"));
    }

    function testSubmitJudgingResultValid() public {
        vm.prank(ALICE); rJudge.submitEncryptedAnswer(bountyId, hex"aa");
        vm.prank(BOB);   rJudge.submitEncryptedAnswer(bountyId, hex"bb");

        vm.warp(block.timestamp + 2 days);

        address[] memory addrs = new address[](2);
        addrs[0] = ALICE; addrs[1] = BOB;
        uint256[] memory scores = new uint256[](2);
        scores[0] = 88; scores[1] = 72;

        rJudge.submitJudgingResult(bountyId, addrs, scores, bytes("attestation"));

        (,,uint256 scA) = rJudge.getSubmissionEncrypted(bountyId, ALICE);
        (,,uint256 scB) = rJudge.getSubmissionEncrypted(bountyId, BOB);
        assertEq(scA, 88);
        assertEq(scB, 72);
    }

    function testSubmitJudgingInvalidAttestation() public {
        vm.prank(ALICE); rJudge.submitEncryptedAnswer(bountyId, hex"aa");
        vm.warp(block.timestamp + 2 days);

        verifier.setValid(false);

        address[] memory addrs = new address[](1);
        addrs[0] = ALICE;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 99;

        vm.expectRevert("invalid attestation");
        rJudge.submitJudgingResult(bountyId, addrs, scores, bytes("bad"));
    }

    function testSubmitJudgingBeforeDeadline() public {
        vm.prank(ALICE); rJudge.submitEncryptedAnswer(bountyId, hex"aa");

        address[] memory addrs = new address[](1);
        addrs[0] = ALICE;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 99;

        vm.expectRevert("submission still open");
        rJudge.submitJudgingResult(bountyId, addrs, scores, bytes("att"));
    }

    function testRitualFinalizeWinner() public {
        vm.prank(ALICE); rJudge.submitEncryptedAnswer(bountyId, hex"aa");
        vm.warp(block.timestamp + 2 days);

        address[] memory addrs = new address[](1);
        addrs[0] = ALICE;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        rJudge.submitJudgingResult(bountyId, addrs, scores, bytes("att"));

        vm.prank(CREATOR);
        rJudge.finalizeWinner(bountyId, 0);

        (,,,uint256 wi,,) = rJudge.getBounty(bountyId);
        assertEq(wi, 0);
    }

    function testRitualFinalizeNonCreator() public {
        vm.prank(ALICE); rJudge.submitEncryptedAnswer(bountyId, hex"aa");
        vm.warp(block.timestamp + 2 days);

        address[] memory addrs = new address[](1);
        addrs[0] = ALICE;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        rJudge.submitJudgingResult(bountyId, addrs, scores, bytes("att"));

        vm.prank(BOB);
        vm.expectRevert("only creator");
        rJudge.finalizeWinner(bountyId, 0);
    }

    function testRitualGetParticipants() public {
        vm.prank(ALICE); rJudge.submitEncryptedAnswer(bountyId, hex"a1");
        vm.prank(BOB);   rJudge.submitEncryptedAnswer(bountyId, hex"b1");

        address[] memory p = rJudge.getParticipants(bountyId);
        assertEq(p.length, 2);
        assertEq(p[0], ALICE);
        assertEq(p[1], BOB);
    }
}

// ═══════════════════════════════════════════════════════
//  Ritual Chain timestamp normalization (ms → seconds)
//  Ritual reports block.timestamp in MILLISECONDS (~1.78e12).
//  The contract auto-detects this and normalises to seconds so that
//  standard SECOND-based deadlines work on any chain.
// ═══════════════════════════════════════════════════════
contract RitualMsTimestampTest is Test {
    function testBountyJudgeMsChainSecondsDeadlinesWork() public {
        // Simulate Ritual's millisecond block.timestamp.
        uint256 msNow = 1_782_418_350_161; // > 1e12 → detected as ms chain
        vm.warp(msNow);
        assertTrue(block.timestamp > 1e12, "precondition: chain now is in ms");

        BountyJudge msJudge = new BountyJudge(address(0x0802));

        // Caller passes STANDARD second-based deadlines (the EVM convention).
        uint256 nowSeconds = msNow / 1000;
        uint256 subDeadline = nowSeconds + 1 days;
        uint256 revDeadline = nowSeconds + 3 days;

        address owner = address(0xCAFE);
        vm.deal(owner, 1 ether);

        // createBounty must succeed despite chain "now" being ~1000x the deadline unit.
        vm.prank(owner);
        uint256 id = msJudge.createBounty{value: 0.01 ether}("ms test", "rubric", subDeadline, revDeadline);
        assertEq(id, 1);

        // A participant can still commit during the submission window.
        address alice = address(0xA11CE);
        bytes32 commitment = keccak256(abi.encodePacked("answer", bytes32(uint256(0xa)), alice, id));
        vm.prank(alice);
        msJudge.submitCommitment(id, commitment);

        (bytes32 stored,, ) = msJudge.getSubmission(id, alice);
        assertTrue(stored != bytes32(0), "commitment stored under ms chain");
    }

    function testRitualBountyJudgeMsChainSecondsDeadlineWork() public {
        uint256 msNow = 1_782_418_350_161;
        vm.warp(msNow);

        MockRitualVerifier verifier = new MockRitualVerifier();
        RitualBountyJudge msJudge = new RitualBountyJudge();

        uint256 nowSeconds = msNow / 1000;
        uint256 deadline = nowSeconds + 1 days;

        // createBounty + encrypted submit must work with second-based deadline on a ms chain.
        uint256 id = msJudge.createBounty(deadline, bytes32(uint256(0xdeadbeef)), address(verifier));
        assertEq(id, 1);

        address alice = address(0xA11CE);
        vm.prank(alice);
        msJudge.submitEncryptedAnswer(id, hex"deadbeef");

        (, bool submitted,) = msJudge.getSubmissionEncrypted(id, alice);
        assertTrue(submitted, "encrypted submit stored under ms chain");
    }
}
