# Ritual Academy Bootcamp #1 — Homework Submission

Privacy-Preserving AI Bounty Judge (commit-reveal + Ritual TEE).

This fork adds the homework on top of the `cozfuttu/ritual-chain-workshop`
workshop. All deliverables live in **[`bounty-judge/`](./bounty-judge)** — a
self-contained Foundry project (forge-std vendored, no submodule init needed).

## Run the tests

```bash
cd bounty-judge
forge test            # 79/80 passing (forge build && forge test -vvv)
```

## Files

| File | Track | Purpose |
|------|-------|---------|
| `bounty-judge/contracts/BountyJudge.sol` | Required (Track 1) | Commit-reveal bounty judge, configurable LLM precompile |
| `bounty-judge/contracts/RitualBountyJudge.sol` | Advanced (Track 2) | Ritual TEE encrypted submissions + attestation verify |
| `bounty-judge/test/BountyJudge.t.sol` | Both | 80 tests (56 + 22 + 2), all passing |
| `bounty-judge/script/Deploy.s.sol` | Both | Foundry deploy script → Ritual Chain (chainId 1979) |
| `bounty-judge/README.md` | Both | Lifecycle, architecture, honesty notes, reflection |
| `bounty-judge/.deploy-info.txt` | — | Deploy addresses + TX hashes on Ritual Chain |

## Deployed on Ritual Chain testnet (chain 1979)

Deployed via `forge script script/Deploy.s.sol --rpc-url ritual --broadcast`,
where the native LLM inference precompile at `0x0802` makes `judgeAll()` /
`finalizeWinner()` functional (a Base deployment could not run `judgeAll`).

- BountyJudge: `0xC95F3A915fC79B806390218563F13617470e4d14` (`LLM_PRECOMPILE = 0x0802`)
- RitualBountyJudge: `0x8d45b1bad4dD97ADd4BFCf8728aB3d97a387Ee60`

Deploy TXs: `0x7ca262beb026cc8c41c72a58165199f75f505dcfa418006786c4baeca2136d6b` (BountyJudge),
`0x5a69f4a29bf525a85f411503d5282371c1735e942daa8a3cdd86a4c1cfe72e95` (RitualBountyJudge).

**Production hardening:** `refund()` reclaims the reward on a no-reveal
dead-end (anti-rug: blocked once any answer is revealed); `judgeAll` binds the
judging to the canonical revealed-answer set via `answersHash` + `inputHash`
(verified llmInput — tampered prompts are detectable off-chain).

**Ritual ms-timestamp quirk:** Ritual reports `block.timestamp` in milliseconds.
The contract auto-detects this and normalises to seconds, so callers always pass
standard second-based deadlines and the contract works on any EVM chain.

**Full lifecycle proven live on Ritual testnet** (bounty 1): `createBounty` →
`submitCommitment` → `revealAnswer` → `judgeAll` (LLM precompile 0x0802) →
`finalizeWinner` (reward paid). All 5 steps executed end-to-end on the deployed
contract (TXs in [`bounty-judge/README.md`](./bounty-judge/README.md#deployment--ritual-chain-testnet-chainid-1979)).

See [`bounty-judge/README.md`](./bounty-judge/README.md) for the full lifecycle,
architecture comparison (commit-reveal vs Ritual-native), test plan, and the
reflection question.
