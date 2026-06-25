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
| `bounty-judge/script/Deploy.s.sol` | Both | Foundry deploy script → Ritual Chain (chainId 1979) |
| `bounty-judge/README.md` | Both | Lifecycle, architecture, honesty notes, reflection |
| `bounty-judge/.deploy-info.txt` | — | Deploy addresses + TX hashes on Ritual Chain |

## Deployed on Ritual Chain (chain 1979)

Deployed via `forge script script/Deploy.s.sol --rpc-url ritual --broadcast`,
where the native LLM inference precompile at `0x0802` makes `judgeAll()` /
`finalizeWinner()` functional (a Base deployment could not run `judgeAll`).

- BountyJudge v2: `0x06a85184E552C3fD1bD0b8d7D178b3FceFdd3dC9` (`LLM_PRECOMPILE = 0x0802`)
- RitualBountyJudge: `0x65C9A64554C11ac9759072150684A683315D6762`

Deploy TXs: `0x55ab4db432f1b69e8b2003f8a9abd47b1741cfc55e7ce672ead84353c5756884` (BountyJudge),
`0x4821d37903e25ca296518c533676655f94250ffe7a39ca30509d2cb397e578f0` (RitualBountyJudge).

See [`bounty-judge/README.md`](./bounty-judge/README.md) for the full lifecycle,
architecture comparison (commit-reveal vs Ritual-native), test plan, and the
reflection question.
