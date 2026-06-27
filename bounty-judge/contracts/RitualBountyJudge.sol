// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title  RitualBountyJudge
 * @notice Advanced Track: privacy-preserving bounty system using Ritual's TEE-backed
 *         execution. Submissions are encrypted client-side — plaintext answers exist
 *         ONLY inside the TEE enclave during LLM batch judging.
 *
 *         Architecture:
 *          ┌─────────────┐    encrypted     ┌────────────────┐
 *          │ Participant │ ───────────────> │   BountyJudge   │
 *          │  (browser)  │   ciphertext     │   (on-chain)    │
 *          └─────────────┘                  └───────┬──────────┘
 *                                                   │ event
 *                                                   ▼
 *                                          ┌────────────────┐
 *                                          │  Ritual TEE     │
 *                                          │  (off-chain)    │
 *                                          │                 │
 *                                          │ 1. Decrypt all  │
 *                                          │ 2. Batch LLM    │
 *                                          │ 3. Submit scores │
 *                                          │    + attestation │
 *                                          └────────────────┘
 *
 *         Key property: plaintext submissions exist ONLY inside the TEE.
 *         The contract never stores them. Only encrypted blobs are on-chain.
 *
 * @custom:ritual  This contract is designed for Ritual Chain / Infernet.
 *                 Uses Ritual's on-chain TEE verification primitives.
 */

// ─── Ritual TEE interface (simplified) ───
interface IRitualVerifier {
    /**
     * @notice  Verify that `output` was produced by a genuine Ritual TEE node
     *          running `enclaveCodeHash` on `input`.
     * @return  valid  True if the attestation is authentic.
     */
    function verifyAttestation(
        bytes32 enclaveCodeHash,
        bytes   calldata input,
        bytes   calldata output,
        bytes   calldata attestation
    ) external view returns (bool valid);
}

contract RitualBountyJudge {
    // ────────────── Errors ──────────────
    error SubmissionWindowClosed();
    error JudgingWindowOpen();
    error JudgingComplete();
    error AlreadySubmitted();
    error InvalidAttestation();
    error OnlyCreator();
    error WinnerAlreadyFinalized();
    error NotEnoughSubmissions();
    error PaymentFailed();
    error NotEligibleForRefund();

    // ────────────── Enums ──────────────
    enum Phase { SUBMISSION, JUDGING, FINALIZED }

    // ────────────── Structs ──────────────
    struct Submission {
        bytes   encryptedAnswer;   // Client-encrypted with Ritual public key
        bool    submitted;
        uint256 score;
    }

    struct Bounty {
        address payable    creator;
        uint256             submissionDeadline;
        uint256             participantCount;
        uint256             winnerIndex;
        uint256             reward;              // locked in contract
        Phase               phase;
        bytes32             enclaveCodeHash;
        IRitualVerifier     verifier;
        mapping(address => Submission) submissions;
        address[]           participants;
    }

    // ────────────── State ──────────────
    mapping(uint256 => Bounty) public bounties;
    uint256 public bountyCount;

    uint256 private _lock = 1;
    modifier nonReentrant() {
        require(_lock == 1, "reentrant");
        _lock = 2;
        _;
        _lock = 1;
    }

    // Ritual Chain reports block.timestamp in MILLISECONDS (verified on-chain).
    // Normalise to seconds so callers always pass SECOND-based deadlines.
    uint256 private constant MS_THRESHOLD = 10 ** 12;
    bool internal immutable USES_MS_TIMESTAMP;

    /// @dev Chain-normalised "now" in SECONDS, regardless of the chain's native unit.
    function _now() internal view returns (uint256) {
        return USES_MS_TIMESTAMP ? block.timestamp / 1000 : block.timestamp;
    }

    // ────────────── Events ──────────────
    event BountyCreated(uint256 bountyId, address creator, uint256 deadline, uint256 reward, bytes32 enclaveCodeHash);
    event EncryptedSubmission(uint256 bountyId, address participant);
    event JudgingExecuted(uint256 bountyId, uint256 scoreCount, bytes attestation);
    event WinnerFinalized(uint256 bountyId, address winner, uint256 score, uint256 reward);
    event RefundClaimed(uint256 bountyId, address creator, uint256 reward);

    // ────────────── Constructor ──────────────
    constructor() {
        USES_MS_TIMESTAMP = block.timestamp > MS_THRESHOLD;
    }

    // ────────────── Bounty Lifecycle ──────────────

    /**
     * @notice  Create a bounty pinned to a specific TEE enclave measurement.
     * @param   _submissionDeadline  When submissions close.
     * @param   _enclaveCodeHash     MRENCLAVE of the Ritual inference container
     *                               that will decrypt & judge answers. This
     *                               guarantees the LLM prompt + model are
     *                               cryptographically fixed.
     * @param   _verifier            Address of Ritual's on-chain attestation
     *                               verifier contract.
     */
    function createBounty(
        uint256 _submissionDeadline,
        bytes32 _enclaveCodeHash,
        address _verifier
    )
        external
        payable
        returns (uint256 bountyId)
    {
        require(_submissionDeadline > _now(), "deadline in past");
        require(msg.value > 0, "reward required");

        unchecked { bountyId = ++bountyCount; }
        Bounty storage b = bounties[bountyId];
        b.creator          = payable(msg.sender);
        b.submissionDeadline = _submissionDeadline;
        b.reward           = msg.value;
        b.enclaveCodeHash  = _enclaveCodeHash;
        b.verifier         = IRitualVerifier(_verifier);
        b.phase            = Phase.SUBMISSION;

        emit BountyCreated(bountyId, msg.sender, _submissionDeadline, msg.value, _enclaveCodeHash);
    }

    // ────────────── Submission Phase ──────────────

    /**
     * @notice  Submit an encrypted answer. The caller encrypts their plaintext
     *          answer client-side using Ritual's public key so that ONLY the
     *          pinned TEE enclave can decrypt it.
     *
     * @dev     The encrypted blob is stored on-chain as calldata. For large
     *          submissions (>~100KB), store the ciphertext on IPFS/Arweave
     *          and submit only the content-hash here.
     *
     * @param   bountyId         ID of the bounty.
     * @param   encryptedAnswer  The answer encrypted with Ritual's TEE public key.
     */
    function submitEncryptedAnswer(uint256 bountyId, bytes calldata encryptedAnswer)
        external
    {
        Bounty storage b = bounties[bountyId];
        require(b.phase == Phase.SUBMISSION, "not in submission");
        require(_now() <= b.submissionDeadline, "deadline passed");
        require(!b.submissions[msg.sender].submitted, "already submitted");

        b.submissions[msg.sender] = Submission({
            encryptedAnswer: encryptedAnswer,
            submitted:       true,
            score:           0
        });
        b.participants.push(msg.sender);
        b.participantCount++;

        emit EncryptedSubmission(bountyId, msg.sender);
    }

    // ────────────── Judging Phase (Ritual TEE) ──────────────

    /**
     * @notice  Called by Ritual's TEE node AFTER the submission deadline.
     *          The TEE node:
     *            1. Reads all encrypted submissions from chain.
     *            2. Decrypts them inside the enclave.
     *            3. Runs a single batch LLM call to score all answers.
     *            4. Calls this function with scores + TEE attestation.
     *
     *          The contract verifies the attestation against the pinned
     *          enclaveCodeHash before accepting the scores.
     *
     * @param   bountyId     ID of the bounty.
     * @param   rankedAddrs  Participants ordered by rank (best first).
     * @param   scores       Corresponding scores (higher = better).
     * @param   attestation  TEE attestation proof (e.g., ECDSA sig from enclave
     *                       over the hash of bountyId + rankedAddrs + scores).
     */
    function submitJudgingResult(
        uint256           bountyId,
        address[] calldata rankedAddrs,
        uint256[] calldata scores,
        bytes     calldata attestation
    )
        external
    {
        Bounty storage b = bounties[bountyId];
        require(b.phase == Phase.SUBMISSION, "not in submission");
        require(_now() > b.submissionDeadline, "submission still open");
        require(rankedAddrs.length == scores.length, "length mismatch");
        require(rankedAddrs.length > 0, "no submissions");

        // 1. Build the input hash the TEE signed over
        bytes memory input = abi.encode(bountyId, rankedAddrs, scores);

        // 2. Build the output the TEE produced (same as input for this
        //    scoring pattern — the "output" IS the ranked list)
        bytes memory output = input;

        // 3. Verify TEE attestation
        bool valid = b.verifier.verifyAttestation(
            b.enclaveCodeHash,
            input,
            output,
            attestation
        );
        require(valid, "invalid attestation");

        // 4. Store scores on-chain
        b.phase = Phase.JUDGING;
        for (uint256 i = 0; i < rankedAddrs.length; i++) {
            Submission storage sub = b.submissions[rankedAddrs[i]];
            require(sub.submitted, "address not a participant");
            sub.score = scores[i];
        }

        emit JudgingExecuted(bountyId, rankedAddrs.length, attestation);
    }

    // ────────────── Finalize ──────────────

    /**
     * @notice  Locks in the winner. Only callable by the bounty creator.
     * @param   bountyId    ID of the bounty.
     * @param   winnerIndex Index into participants array of the winner.
     */
    function finalizeWinner(uint256 bountyId, uint256 winnerIndex)
        external
        nonReentrant
    {
        Bounty storage b = bounties[bountyId];
        require(msg.sender == b.creator, "only creator");
        require(b.phase == Phase.JUDGING, "not in judging");
        require(winnerIndex < b.participantCount, "invalid index");

        address winner = b.participants[winnerIndex];
        require(b.submissions[winner].score > 0, "not scored");

        b.winnerIndex = winnerIndex;
        b.phase       = Phase.FINALIZED;
        uint256 reward = b.reward;
        b.reward      = 0;

        (bool ok, ) = payable(winner).call{value: reward}("");
        require(ok, "payment failed");

        emit WinnerFinalized(bountyId, winner, b.submissions[winner].score, reward);
    }

    /// @notice Creator reclaims reward when no valid submissions exist after deadline.
    function refund(uint256 bountyId)
        external
        nonReentrant
    {
        Bounty storage b = bounties[bountyId];
        require(msg.sender == b.creator, "only creator");
        require(_now() > b.submissionDeadline, "deadline not passed");
        require(b.phase == Phase.SUBMISSION, "already judging");
        if (b.participantCount != 0) revert NotEligibleForRefund();

        b.phase = Phase.FINALIZED;
        uint256 reward = b.reward;
        b.reward = 0;
        (bool ok, ) = payable(msg.sender).call{value: reward}("");
        require(ok, "refund failed");
        emit RefundClaimed(bountyId, msg.sender, reward);
    }

    // ────────────── Views ──────────────

    function getBounty(uint256 bountyId)
        external view returns (
            address creator,
            uint256 submissionDeadline,
            uint256 participantCount,
            uint256 winnerIndex,
            Phase   phase,
            bytes32 enclaveCodeHash
        )
    {
        Bounty storage b = bounties[bountyId];
        return (
            b.creator,
            b.submissionDeadline,
            b.participantCount,
            b.winnerIndex,
            b.phase,
            b.enclaveCodeHash
        );
    }

    function getSubmissionEncrypted(uint256 bountyId, address participant)
        external view returns (bytes memory encryptedAnswer, bool submitted, uint256 score)
    {
        Submission storage sub = bounties[bountyId].submissions[participant];
        return (sub.encryptedAnswer, sub.submitted, sub.score);
    }

    function getParticipants(uint256 bountyId)
        external view returns (address[] memory)
    {
        return bounties[bountyId].participants;
    }
}
