# Ritual Academy Bootcamp #1 — Homework Submission

Privacy-Preserving AI Bounty Judge (commit-reveal + Ritual TEE).

This fork adds the homework on top of the `cozfuttu/ritual-chain-workshop`
workshop. All deliverables live in **[`bounty-judge/`](./bounty-judge)** — a
self-contained Foundry project (forge-std vendored, no submodule init needed).

## Run the tests

```bash
cd bounty-judge
forge test            # 44/44 passing (forge build && forge test -vvv)
```

## Files

| File | Track | Purpose |
|------|-------|---------|
| `bounty-judge/contracts/BountyJudge.sol` | Required (Track 1) | Commit-reveal bounty judge, configurable LLM precompile |
| `bounty-judge/contracts/RitualBountyJudge.sol` | Advanced (Track 2) | Ritual TEE encrypted submissions + attestation verify |
| `bounty-judge/test/BountyJudge.t.sol` | Both | 44 tests (34 + 10), all passing |
| `bounty-judge/README.md` | Both | Lifecycle, architecture, honesty notes, reflection |
| `bounty-judge/.deploy-info.txt` | — | Deploy addresses + TX hashes on Base mainnet |

## Deployed on Base Mainnet (chain 8453)

- BountyJudge v2: `0x71Dda5aEC3885B197d650BADA995D10f382d7793` (Sourcify exact_match)
- RitualBountyJudge: `0x983c4Ff16882793e582C5D402A75e9045Ca881B2` (Sourcify exact_match)

See [`bounty-judge/README.md`](./bounty-judge/README.md) for the full lifecycle,
architecture comparison (commit-reveal vs Ritual-native), test plan, and the
reflection question.
