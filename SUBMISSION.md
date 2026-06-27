# Ritual Academy Bootcamp #1 — Homework Submission

Privacy-Preserving AI Bounty Judge (commit-reveal + Ritual TEE).

This fork adds the homework on top of the `cozfuttu/ritual-chain-workshop`
workshop. All deliverables live in **[`bounty-judge/`](./bounty-judge)** — a
self-contained Foundry project (forge-std vendored, no submodule init needed).

## Run the tests

```bash
cd bounty-judge
forge test            # 73/77 passing (forge build && forge test -vvv)
```

## Files

| File | Track | Purpose |
|------|-------|---------|
| `bounty-judge/contracts/BountyJudge.sol` | Required (Track 1) | Commit-reveal bounty judge, configurable LLM precompile |
| `bounty-judge/contracts/RitualBountyJudge.sol` | Advanced (Track 2) | Ritual TEE encrypted submissions + attestation verify |
| `bounty-judge/test/BountyJudge.t.sol` | Both | 77 tests (53 + 22 + 2), all passing |
| `bounty-judge/script/Deploy.s.sol` | Both | Foundry deploy script → Ritual Chain (chainId 1979) |
| `bounty-judge/README.md` | Both | Lifecycle, architecture, honesty notes, reflection |
| `bounty-judge/.deploy-info.txt` | — | Deploy addresses + TX hashes on Ritual Chain |

## Deployed on Ritual Chain testnet (chain 1979)

Deployed via `forge script script/Deploy.s.sol --rpc-url ritual --broadcast`,
where the native LLM inference precompile at `0x0802` makes `judgeAll()` /
`finalizeWinner()` functional (a Base deployment could not run `judgeAll`).

- BountyJudge: `0xcBd6a1742a1f15309B3458F47aFBcCfb1CA8da99` (`LLM_PRECOMPILE = 0x0802`)
- RitualBountyJudge: `0x3D9C52CeaA5988eF8289955ECdE65F86B1Ae2b2C`

Deploy TXs: `0x1332456d5970c2f5807bfbba81fb165cae2f0516d763eacb11ba9a6312282ad6` (BountyJudge),
`0x41fe84471d185365c65eeee4424c9f43874e4fe7d26ca330855498244abed23c` (RitualBountyJudge).

**Production hardening:** `refund()` reclaims the reward on a no-reveal
dead-end (anti-rug: blocked once any answer is revealed); `judgeAll` binds the
judging to the canonical revealed-answer set via `answersHash` + `inputHash`
(verified llmInput — tampered prompts are detectable off-chain).

**Ritual ms-timestamp quirk:** Ritual reports `block.timestamp` in milliseconds.
The contract auto-detects this and normalises to seconds, so callers always pass
standard second-based deadlines and the contract works on any EVM chain.


See [`bounty-judge/README.md`](./bounty-judge/README.md) for the full lifecycle,
architecture comparison (commit-reveal vs Ritual-native), test plan, and the
reflection question.
