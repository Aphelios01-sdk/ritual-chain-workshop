// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title  IRitualWallet
 * @notice Interface for the Ritual wallet used to lock bounty rewards.
 *         Identical to the workshop interface.
 */
/**
 * @title  PrecompileConsumer
 * @notice Base contract for Ritual Chain precompile access.
 *         Provides the LLM_INFERENCE_PRECOMPILE at 0x0802 and
 *         helper _executePrecompile() for calling Ritual precompiles.
 *         (Identical to the workshop base contract.)
 */
abstract contract PrecompileConsumer {
    // Short-running async precompile for LLM inference
    address internal constant LLM_INFERENCE_PRECOMPILE = address(0x0802);

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
 * @title  IRitualWallet
 * @notice Interface for the Ritual wallet used to lock bounty rewards.
 *         Identical to the workshop interface.
 */
interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address user, uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
    function lockUntil(address) external view returns (uint256);
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
    uint256 public constant MAX_ANSWER_LENGTH = 2_000;

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
        mapping(address => Submission) submissions;
        address[] participants;       // ordered array — index = position
    }

    // ────────────── State ──────────────
    uint256 public nextBountyId = 1;
    mapping(uint256 => Bounty) public bounties;

    // LLM inference precompile — configurable per deployment
    // On Ritual Chain: 0x0802. On other EVM chains: an equivalent LLM contract address.
    address public immutable LLM_PRECOMPILE;

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
        bytes   aiReview
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
        require(_submissionDeadline > block.timestamp, "submission deadline in past");
        require(_revealDeadline > _submissionDeadline, "reveal before submission");

        bountyId = nextBountyId++;
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
        require(block.timestamp <= b.submissionDeadline, "submission deadline passed");
        require(b.submissions[msg.sender].commitment == bytes32(0), "already submitted");

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
        if (b.phase == Phase.SUBMISSION && block.timestamp <= b.submissionDeadline) {
            revert StillInSubmission();
        }
        // Cannot reveal after finalized
        if (b.phase == Phase.FINALIZED) revert AlreadyFinalized();
        // Cannot reveal after reveal deadline
        require(block.timestamp <= b.revealDeadline, "reveal deadline passed");

        Submission storage sub = b.submissions[msg.sender];
        require(sub.commitment != bytes32(0), "no commitment");
        require(!sub.revealed, "already revealed");
        require(bytes(answer).length <= MAX_ANSWER_LENGTH, "answer too long");

        // Auto-advance phase
        if (b.phase == Phase.SUBMISSION) {
            b.phase = Phase.REVEAL;
        }

        // Verify: keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
        bytes32 computed = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
        require(computed == sub.commitment, "invalid commitment");

        sub.answer   = answer;
        sub.revealed = true;
        b.revealedCount++;

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
        require(block.timestamp > b.revealDeadline, "reveal deadline not passed");

        // Count revealed submissions for sanity check (O(1))
        uint256 revealedCount = b.revealedCount;
        require(revealedCount > 0, "no revealed submissions");

        // Call Ritual's LLM inference precompile
        bytes memory output = _executePrecompile(
            LLM_PRECOMPILE,
            llmInput
        );

        b.judged       = true;
        b.aiReview     = output;

        emit AllAnswersJudged(bountyId, output);
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
     * @notice  Get one participant's submission.
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
        return (sub.commitment, sub.answer, sub.revealed);
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
