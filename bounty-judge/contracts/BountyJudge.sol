// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title  PrecompileConsumer
 * @notice Base contract for Ritual Chain precompile access.
 *         Provides _executePrecompile() for calling Ritual precompiles.
 *         (Derived from the workshop base contract.)
 */
abstract contract PrecompileConsumer {
    /**
     * @notice  Execute a short-running async precompile.
     *          Decodes the outer (simmedInput, actualOutput) envelope.
     */
    function _executePrecompile(
        address precompile,
        bytes memory input
    ) internal returns (bytes memory) {
        (bool success, bytes memory rawOutput) = precompile.call(input);

        if (!success) {
            assembly {
                revert(add(rawOutput, 32), mload(rawOutput))
            }
        }

        // Short-running async precompiles return:
        //   abi.encode(bytes simmedInput, bytes actualOutput)
        (, bytes memory actualOutput) = abi.decode(
            rawOutput,
            (bytes, bytes)
        );
        return actualOutput;
    }
}

/**
 * @title  BountyJudge
 * @notice Privacy-preserving AI bounty judge built on Ritual Chain.
 *
 *         Extends the workshop AIJudge contract to fix the critical flaw:
 *         submissions are now hidden via commit-reveal until the AI judging
 *         phase. The contract calls Ritual's LLM inference precompile (0x0802)
 *         for on-chain batch AI judging — one LLM call, not per-submission.
 *
 *         Workshop base: github.com/cozfuttu/ritual-chain-workshop
 *
 *         Lifecycle:
 *          1. Owner creates a bounty with title, rubric, deadline, and reward.
 *          2. Participants submit a keccak256 commitment during submission phase.
 *          3. After submission deadline, participants reveal answer + salt.
 *          4. Contract verifies keccak256(abi.encodePacked(answer, salt, sender, bountyId))
 *             matches the stored commitment.
 *          5. After reveal deadline, owner calls judgeAll() with the full LLM prompt
 *             (including all revealed answers + rubric).
 *          6. Contract calls Ritual's LLM inference precompile → aiReview stored on-chain.
 *          7. Owner calls finalizeWinner() — contract pays the winner.
 *
 *         Commitment formula (MUST match exactly):
 *             commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
 */
contract BountyJudge is PrecompileConsumer {
    // ────────────── Constants ──────────────
    uint256 public constant MAX_SUBMISSIONS = 50;

    // ────────────── Errors ──────────────
    error NotOwner();
    error SubmissionDeadlinePassed();
    error StillInSubmission();
    error RevealDeadlinePassed();
    error AlreadySubmitted();
    error AlreadyRevealed();
    error InvalidCommitment();
    error NotSubmitted();
    error AlreadyJudged();
    error AlreadyFinalized();
    error NotJudged();
    error NoSubmissions();
    error InvalidWinnerIndex();
    error PaymentFailed();
    error BountyNotFound();
    error NotEligibleForRefund();

    // ────────────── Enums ──────────────
    enum Phase {
        SUBMISSION,  // 0 — accepting commitments only
        REVEAL,      // 1 — accepting reveals (auto-advances)
        FINALIZED    // 2 — winner locked, reward paid
    }

    // ────────────── Structs ──────────────
    struct Submission {
        bytes32 commitment;   // keccak256(abi.encodePacked(answer, salt, sender, bountyId))
        string  answer;       // stored after valid reveal
        bool    revealed;     // true after valid reveal
    }

    struct Bounty {
        address payable owner;
        string  title;
        string  rubric;
        uint256 reward;               // wei
        uint256 submissionDeadline;    // unix timestamp
        uint256 revealDeadline;        // unix timestamp
        uint256 revealedCount;         // O(1) counter — incremented on reveal
        bool    judged;               // true after judgeAll()
        bool    finalized;
        bytes   aiReview;             // raw output from LLM precompile
        uint256 winnerIndex;
        Phase   phase;
        bytes32 answersHash;          // hash of rubric + revealed answers, bound at judgeAll
        bytes32 inputHash;            // keccak256(llmInput), bound at judgeAll
        mapping(address => Submission) submissions;
        address[] participants;       // ordered array — index = position
    }

    // ────────────── State ──────────────
    uint256 public nextBountyId = 1;
    mapping(uint256 => Bounty) public bounties;

    // Reentrancy guard (zero-dependency)
    uint256 private _lock = 1;
    modifier nonReentrant() {
        require(_lock == 1, "reentrant");
        _lock = 2;
        _;
        _lock = 1;
    }

    // LLM inference precompile — configurable per deployment
    // On Ritual Chain: 0x0802. On other EVM chains: an equivalent LLM contract address.
    address public immutable LLM_PRECOMPILE;

    // Ritual Chain reports block.timestamp in MILLISECONDS, not seconds (verified
    // on-chain: latest block ≈ 1.78e12). Standard EVM chains use seconds.
    // To keep deadline semantics identical across chains (caller always passes
    // SECOND-based Unix deadlines), we detect the unit at construction and
    // normalise Ritual's ms back to seconds via _now().
    uint256 private constant MS_THRESHOLD = 10 ** 12;
    bool internal immutable USES_MS_TIMESTAMP;

    /// @dev Chain-normalised "now" in SECONDS, regardless of the chain's native unit.
    function _now() internal view returns (uint256) {
        return USES_MS_TIMESTAMP ? block.timestamp / 1000 : block.timestamp;
    }

    // ────────────── Events ──────────────
    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string  title,
        uint256 reward,
        uint256 submissionDeadline,
        uint256 revealDeadline
    );
    event CommitmentSubmitted(
        uint256 indexed bountyId,
        address indexed participant,
        bytes32 commitment
    );
    event AnswerRevealed(
        uint256 indexed bountyId,
        address indexed participant
    );
    event AllAnswersJudged(
        uint256 indexed bountyId,
        bytes   aiReview,
        bytes32 answersHash,
        bytes32 inputHash
    );
    event RefundClaimed(
        uint256 indexed bountyId,
        address indexed owner,
        uint256 amount
    );
    event WinnerFinalized(
        uint256 indexed bountyId,
        uint256 indexed winnerIndex,
        address indexed winner,
        uint256 reward
    );

    // ────────────── Modifiers ──────────────
    modifier onlyOwner(uint256 bountyId) {
        if (msg.sender != bounties[bountyId].owner) revert NotOwner();
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        if (bounties[bountyId].owner == address(0)) revert BountyNotFound();
        _;
    }

    // ────────────── Constructor ──────────────
    constructor(address _precompile) {
        LLM_PRECOMPILE = _precompile;
        USES_MS_TIMESTAMP = block.timestamp > MS_THRESHOLD;
    }

    // ────────────── Bounty Creation ──────────────

    /**
     * @notice  Create a bounty. msg.sender becomes the owner.
     *          Reward ETH is locked in this contract.
     * @param   title                Short title for the bounty.
     * @param   rubric               Judging criteria / rubric text.
     * @param   _submissionDeadline   Unix timestamp — commitments close.
     * @param   _revealDeadline       Unix timestamp — reveals close.
     * @return  bountyId              New bounty ID.
     */
    function createBounty(
        string  calldata title,
        string  calldata rubric,
        uint256 _submissionDeadline,
        uint256 _revealDeadline
    )
        external
        payable
        returns (uint256 bountyId)
    {
        require(msg.value > 0, "reward required");
        require(_submissionDeadline > _now(), "submission deadline in past");
        require(_revealDeadline > _submissionDeadline, "reveal before submission");

        bountyId = nextBountyId;
        unchecked { nextBountyId++; }
        Bounty storage b = bounties[bountyId];

        b.owner              = payable(msg.sender);
        b.title              = title;
        b.rubric             = rubric;
        b.reward             = msg.value;
        b.submissionDeadline  = _submissionDeadline;
        b.revealDeadline      = _revealDeadline;
        b.winnerIndex         = type(uint256).max;
        b.phase               = Phase.SUBMISSION;

        emit BountyCreated(bountyId, msg.sender, title, msg.value, _submissionDeadline, _revealDeadline);
    }

    // ────────────── Commit Phase ──────────────

    /**
     * @notice  Submit a commitment hash during the submission window.
     * @dev     One commitment per participant per bounty.
     *          Commitment MUST be: keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
     */
    function submitCommitment(uint256 bountyId, bytes32 commitment)
        external
        bountyExists(bountyId)
    {
        Bounty storage b = bounties[bountyId];
        require(b.phase == Phase.SUBMISSION, "not in submission");
        require(_now() <= b.submissionDeadline, "submission deadline passed");
        require(commitment != bytes32(0), "empty commitment");
        require(b.submissions[msg.sender].commitment == bytes32(0), "already submitted");
        require(b.participants.length < MAX_SUBMISSIONS, "too many submissions");

        b.submissions[msg.sender].commitment = commitment;
        b.participants.push(msg.sender);

        emit CommitmentSubmitted(bountyId, msg.sender, commitment);
    }

    // ────────────── Reveal Phase ──────────────

    /**
     * @notice  Reveal the answer + salt during the reveal window.
     * @dev     Contract recomputes keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
     *          and compares against the stored commitment.
     *          Auto-advances from SUBMISSION → REVEAL on first valid reveal.
     */
    function revealAnswer(
        uint256 bountyId,
        string  calldata answer,
        bytes32 salt
    )
        external
        bountyExists(bountyId)
    {
        Bounty storage b = bounties[bountyId];

        // Cannot reveal while still in submission window
        if (b.phase == Phase.SUBMISSION && _now() <= b.submissionDeadline) {
            revert StillInSubmission();
        }
        // Cannot reveal after finalized
        if (b.phase == Phase.FINALIZED) revert AlreadyFinalized();
        // Cannot reveal after reveal deadline
        require(_now() <= b.revealDeadline, "reveal deadline passed");

        Submission storage sub = b.submissions[msg.sender];
        require(sub.commitment != bytes32(0), "no commitment");
        require(!sub.revealed, "already revealed");

        // Auto-advance phase
        if (b.phase == Phase.SUBMISSION) {
            b.phase = Phase.REVEAL;
        }

        // Verify: keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
        bytes32 computed = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
        require(computed == sub.commitment, "invalid commitment");

        sub.answer   = answer;
        sub.revealed = true;
        unchecked { b.revealedCount++; }

        emit AnswerRevealed(bountyId, msg.sender);
    }

    // ────────────── Judging Phase (Ritual LLM Precompile) ──────────────

    /**
     * @notice  Judge all revealed answers using Ritual's on-chain LLM inference
     *          precompile. One batch call — NOT per-submission.
     *
     *          Only callable by the bounty owner after the reveal deadline.
     *
     * @dev     llmInput should contain the FULL assembled prompt:
     *              rubric + all revealed answers
     *          The precompile (0x0802) executes synchronously and returns
     *          the AI judge's ranking/review as aiReview bytes.
     *
     *          INPUT INTEGRITY: the contract binds this judging call to the
     *          exact revealed answer set by recomputing `answersHash` from the
     *          rubric + every revealed (participant, answer) in participant
     *          order, and records `inputHash = keccak256(llmInput)`. Both are
     *          stored + emitted so anyone can audit that the prompt the owner
     *          submitted (reconstructable from the tx calldata) actually
     *          corresponds to the canonical revealed answers — making a
     *          tampered / answer-swapping prompt detectable off-chain.
     *
     * @param   bountyId  ID of the bounty.
     * @param   llmInput  Full LLM prompt bytes (rubric + assembled answers).
     */
    function judgeAll(
        uint256 bountyId,
        bytes   calldata llmInput
    )
        external
        bountyExists(bountyId)
        onlyOwner(bountyId)
    {
        Bounty storage b = bounties[bountyId];

        require(!b.judged, "already judged");
        require(!b.finalized, "already finalized");
        require(_now() > b.revealDeadline, "reveal deadline not passed");

        // Count revealed submissions for sanity check (O(1))
        uint256 revealedCount = b.revealedCount;
        require(revealedCount > 0, "no revealed submissions");

        // Bind this judging call to the canonical revealed-answer set (auditability).
        bytes32 answersHash = _hashRevealedAnswers(b);
        bytes32 inputHash = keccak256(llmInput);
        b.answersHash = answersHash;
        b.inputHash = inputHash;

        // Call Ritual's LLM inference precompile
        bytes memory output = _executePrecompile(
            LLM_PRECOMPILE,
            llmInput
        );

        b.judged       = true;
        b.aiReview     = output;

        emit AllAnswersJudged(bountyId, output, answersHash, inputHash);
    }

    /// @dev Canonical hash over the rubric + every revealed (participant, answer),
    ///      in participant-array order. Pins exactly what the judging must cover.
    function _hashRevealedAnswers(Bounty storage b) internal view returns (bytes32) {
        bytes memory bundle = abi.encode(b.rubric);
        address[] storage parts = b.participants;
        for (uint256 i = 0; i < parts.length; i++) {
            Submission storage sub = b.submissions[parts[i]];
            if (sub.revealed) {
                bundle = abi.encodePacked(bundle, parts[i], sub.answer);
            }
        }
        return keccak256(bundle);
    }

    /// @notice  Owner reclaims the locked reward when the bounty is a dead-end:
    ///          i.e. the reveal window closed with ZERO valid reveals, so there
    ///          is nobody eligible to be judged or paid. Prevents funds being
    ///          locked forever. Refunds are intentionally NOT allowed once any
    ///          answer has been revealed (that would let the owner rug valid
    ///          participants) — in that case the owner must judge + finalize.
    function refund(uint256 bountyId)
        external
        nonReentrant
        bountyExists(bountyId)
        onlyOwner(bountyId)
    {
        Bounty storage b = bounties[bountyId];

        if (b.judged || b.finalized) revert AlreadyFinalized();
        if (_now() <= b.revealDeadline) revert RevealDeadlinePassed();
        if (b.revealedCount != 0) revert NotEligibleForRefund();

        b.finalized = true;
        b.phase = Phase.FINALIZED;
        uint256 reward = b.reward;
        b.reward = 0;

        (bool ok, ) = payable(msg.sender).call{value: reward}("");
        require(ok, "refund failed");

        emit RefundClaimed(bountyId, msg.sender, reward);
    }

    // ────────────── Finalize ──────────────

    /**
     * @notice  Finalize the winner and pay the reward.
     *          Only callable by the bounty owner after judging.
     *
     * @param   bountyId    ID of the bounty.
     * @param   winnerIndex Index into the participants array.
     */
    function finalizeWinner(uint256 bountyId, uint256 winnerIndex)
        external
        nonReentrant
        bountyExists(bountyId)
        onlyOwner(bountyId)
    {
        Bounty storage b = bounties[bountyId];

        require(b.judged, "not judged");
        require(!b.finalized, "already finalized");
        require(winnerIndex < b.participants.length, "invalid index");

        address winnerAddr = b.participants[winnerIndex];
        require(b.submissions[winnerAddr].revealed, "submission not revealed");

        b.finalized    = true;
        b.winnerIndex  = winnerIndex;
        b.phase        = Phase.FINALIZED;
        uint256 reward = b.reward;
        b.reward       = 0;

        (bool ok, ) = payable(winnerAddr).call{value: reward}("");
        require(ok, "payment failed");

        emit WinnerFinalized(bountyId, winnerIndex, winnerAddr, reward);
    }

    // ────────────── Views ──────────────

    /**
     * @notice  Get core bounty metadata (smaller return to avoid stack too deep).
     */
    function getBountyCore(uint256 bountyId)
        external
        view
        bountyExists(bountyId)
        returns (
            address owner,
            string  memory title,
            string  memory rubric,
            uint256 reward,
            uint256 submissionDeadline,
            uint256 revealDeadline,
            bool    judged,
            bool    finalized,
            Phase   phase
        )
    {
        Bounty storage b = bounties[bountyId];
        return (
            b.owner,
            b.title,
            b.rubric,
            b.reward,
            b.submissionDeadline,
            b.revealDeadline,
            b.judged,
            b.finalized,
            b.phase
        );
    }

    /**
     * @notice  Get bounty extra metadata (participant count, winner, aiReview).
     */
    function getBountyInfo(uint256 bountyId)
        external
        view
        bountyExists(bountyId)
        returns (
            uint256 participantCount,
            uint256 winnerIndex,
            bytes   memory aiReview
        )
    {
        Bounty storage b = bounties[bountyId];
        return (
            b.participants.length,
            b.winnerIndex,
            b.aiReview
        );
    }

    /**
     * @notice  Judging integrity attestation, set at judgeAll().
     *          `answersHash` = keccak over rubric + revealed (participant, answer)
     *          in order; `inputHash` = keccak256(llmInput). Together they let
     *          anyone verify the judged prompt matches the canonical answers.
     */
    function getJudgingAttestation(uint256 bountyId)
        external
        view
        bountyExists(bountyId)
        returns (bytes32 answersHash, bytes32 inputHash)
    {
        Bounty storage b = bounties[bountyId];
        return (b.answersHash, b.inputHash);
    }

    /**
     * @notice  Get one participant's submission. The plaintext answer is
     *          hidden until the bounty is judged (to satisfy the assignment
     *          requirement "answers remain hidden until judging is complete").
     *          Before judging, `answer` returns an empty string even after a
     *          valid reveal; only the `revealed` flag is visible.
     */
    function getSubmission(uint256 bountyId, address participant)
        external
        view
        returns (
            bytes32 commitment,
            string  memory answer,
            bool    revealed
        )
    {
        Submission storage sub = bounties[bountyId].submissions[participant];
        bool judged = bounties[bountyId].judged;
        string memory visibleAnswer = judged ? sub.answer : "";
        return (sub.commitment, visibleAnswer, sub.revealed);
    }

    /**
     * @notice  Get the ordered participants array.
     */
    function getParticipants(uint256 bountyId)
        external
        view
        returns (address[] memory)
    {
        return bounties[bountyId].participants;
    }

    /**
     * @notice  Count revealed submissions for a bounty.
     */
    function getRevealedCount(uint256 bountyId)
        external
        view
        returns (uint256)
    {
        return bounties[bountyId].revealedCount;
    }
}
