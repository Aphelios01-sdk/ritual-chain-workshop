# Ritual Academy Bootcamp #1 — Homework Submission

Fork of [cozfuttu/ritual-chain-workshop](https://github.com/cozfuttu/ritual-chain-workshop).

## Repository layout

| Directory | What it is |
|---|---|
| **`bounty-judge/`** | **Homework submission** — Foundry project with the commit-reveal `BountyJudge` (Track 1), Ritual TEE `RitualBountyJudge` (Track 2), 52 tests, and deploy script. See [`bounty-judge/README.md`](./bounty-judge/README.md) for the full lifecycle, architecture comparison, and reflection. |
| `hardhat/` | Original workshop starter. Contains the unmodified `AIJudge.sol` (public submissions — the flaw we fix in the homework). Not used by the submission. |
| `web/` | Original workshop frontend. Built for `AIJudge.sol` (public `submitAnswer` flow). Not wired to the commit-reveal `BountyJudge`. |

## Quick start

```bash
# Run the homework test suite
cd bounty-judge
forge test                   # 52/52 passing

# Deploy to Ritual Chain testnet
cp .env.example .env         # set RITUAL_RPC_URL + DEPLOYER_PRIVATE_KEY
forge script script/Deploy.s.sol --rpc-url ritual --broadcast
```

## Deployed (Ritual testnet, chainId 1979)

- BountyJudge v3: `0x97e1907022c1AE5B276F2D45907DF96399a38c4F`
- RitualBountyJudge: `0x35Cd23637A8C5a8a61fD9A32D49A2fc1250f5A09`

RPC: `https://rpc.ritualfoundation.org` · Explorer: `https://explorer.ritualfoundation.org`
