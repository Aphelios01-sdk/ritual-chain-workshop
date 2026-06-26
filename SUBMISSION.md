# Ritual Academy Bootcamp #1 — Homework Submission

Privacy-Preserving AI Bounty Judge (commit-reveal + Ritual TEE).

This fork adds the homework on top of the `cozfuttu/ritual-chain-workshop`
workshop. All deliverables live in **[`bounty-judge/`](./bounty-judge)** — a
self-contained Foundry project (forge-std vendored, no submodule init needed).

## Run the tests

```bash
cd bounty-judge
forge test            # 54/54 passing (forge build && forge test -vvv)
```

## Files

| File | Track | Purpose |
|------|-------|---------|
| `bounty-judge/contracts/BountyJudge.sol` | Required (Track 1) | Commit-reveal bounty judge, configurable LLM precompile |
| `bounty-judge/contracts/RitualBountyJudge.sol` | Advanced (Track 2) | Ritual TEE encrypted submissions + attestation verify |
| `bounty-judge/test/BountyJudge.t.sol` | Both | 54 tests (42 + 10 + 2), all passing |
| `bounty-judge/script/Deploy.s.sol` | Both | Foundry deploy script → Ritual Chain (chainId 1979) |
| `bounty-judge/README.md` | Both | Lifecycle, architecture, honesty notes, reflection |
| `bounty-judge/.deploy-info.txt` | — | Deploy addresses + TX hashes on Ritual Chain |

## Deployed on Ritual Chain testnet (chain 1979)

Deployed via `forge script script/Deploy.s.sol --rpc-url ritual --broadcast`,
where the native LLM inference precompile at `0x0802` makes `judgeAll()` /
`finalizeWinner()` functional (a Base deployment could not run `judgeAll`).

- BountyJudge: `0x97e1907022c1AE5B276F2D45907DF96399a38c4F` (`LLM_PRECOMPILE = 0x0802`)
- RitualBountyJudge: `0x35Cd23637A8C5a8a61fD9A32D49A2fc1250f5A09`

Deploy TXs: `0x46320bfc7abe1539d82496ba13be748fd490c5a0346f7b03eb3d42724a8b5a80` (BountyJudge),
`0xf8125545622f984a676d190f34fe0c2b24c4990a79aceb94e4af3a86cb53507b` (RitualBountyJudge).

**Production hardening:** `refund()` reclaims the reward on a no-reveal
dead-end (anti-rug: blocked once any answer is revealed); `judgeAll` binds the
judging to the canonical revealed-answer set via `answersHash` + `inputHash`
(verified llmInput — tampered prompts are detectable off-chain).

**Ritual ms-timestamp quirk:** Ritual reports `block.timestamp` in milliseconds.
The contract auto-detects this and normalises to seconds, so callers always pass
standard second-based deadlines and the contract works on any EVM chain.

**Proved live on Ritual testnet (bounty 2, two participants):** `createBounty`
→ `submitCommitment` ×2 → `revealAnswer` ×2 (both commitments verified against
`keccak256(answer, salt, msg.sender, bountyId)`, `revealedCount == 2`). TXs:
`0x05a19b02..`, `0x2e50ef72..`, `0xcd78b357..`, `0xb51211e6..`, `0x6e692a3a..`.
`judgeAll` was attempted live; it requires a TEE-registered executor
(`0xB42e435c...`) and a fixed 0.311 RITUAL wallet reservation the deployer lacked,
so the live LLM step is documented rather than completed (fully covered in the
46-test suite with a mocked precompile).

See [`bounty-judge/README.md`](./bounty-judge/README.md) for the full lifecycle,
architecture comparison (commit-reveal vs Ritual-native), test plan, and the
reflection question.
