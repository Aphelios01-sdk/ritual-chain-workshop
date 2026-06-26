# Ritual Academy Bootcamp #1 — Homework Submission

Privacy-Preserving AI Bounty Judge (commit-reveal + Ritual TEE).

This fork adds the homework on top of the `cozfuttu/ritual-chain-workshop`
workshop. All deliverables live in **[`bounty-judge/`](./bounty-judge)** — a
self-contained Foundry project (forge-std vendored, no submodule init needed).

## Run the tests

```bash
cd bounty-judge
forge test            # 46/46 passing (forge build && forge test -vvv)
```

## Files

| File | Track | Purpose |
|------|-------|---------|
| `bounty-judge/contracts/BountyJudge.sol` | Required (Track 1) | Commit-reveal bounty judge, configurable LLM precompile |
| `bounty-judge/contracts/RitualBountyJudge.sol` | Advanced (Track 2) | Ritual TEE encrypted submissions + attestation verify |
| `bounty-judge/test/BountyJudge.t.sol` | Both | 46 tests (34 + 10 + 2), all passing |
| `bounty-judge/script/Deploy.s.sol` | Both | Foundry deploy script → Ritual Chain (chainId 1979) |
| `bounty-judge/README.md` | Both | Lifecycle, architecture, honesty notes, reflection |
| `bounty-judge/.deploy-info.txt` | — | Deploy addresses + TX hashes on Ritual Chain |

## Deployed on Ritual Chain testnet (chain 1979)

Deployed via `forge script script/Deploy.s.sol --rpc-url ritual --broadcast`,
where the native LLM inference precompile at `0x0802` makes `judgeAll()` /
`finalizeWinner()` functional (a Base deployment could not run `judgeAll`).

- BountyJudge v2: `0x2B75AE3b7F6522ED66BE4Df1432E2a283058cef0` (`LLM_PRECOMPILE = 0x0802`)
- RitualBountyJudge: `0x4a8358919c82562489D0ca7ae3b22C6089DC8Ca6`

Deploy TXs: `0x4072ca96441010fd013a18f52d5055f4351fb692209397468e995e10b7ad4753` (BountyJudge),
`0x174c95e124137225ba8469c176ac007632272fb45c9ffebb3239b8615212fd32` (RitualBountyJudge).

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
