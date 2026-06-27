# Ritual Academy Bootcamp #1 — Homework Submission

Fork of [cozfuttu/ritual-chain-workshop](https://github.com/cozfuttu/ritual-chain-workshop).

## Repository layout

| Directory | What it is |
|---|---|
| **`bounty-judge/`** | **Homework submission** — Foundry project with the commit-reveal `BountyJudge` (Track 1), Ritual TEE `RitualBountyJudge` (Track 2), 80 tests, deploy script. See [`bounty-judge/README.md`](./bounty-judge/README.md). |
| `web/` | Frontend migrated to commit-reveal (SubmitCommitment, RevealAnswer, CommitmentsList). Uses ABI + address from `bounty-judge/`. |

## Quick start

```bash
# Run the homework test suite
cd bounty-judge
forge test                   # 79/80 passing

# Deploy to Ritual Chain testnet
cp .env.example .env         # set RITUAL_RPC_URL + DEPLOYER_PRIVATE_KEY
forge script script/Deploy.s.sol --rpc-url ritual --broadcast
```

## Deployed (Ritual testnet, chainId 1979)

- BountyJudge: `0xC95F3A915fC79B806390218563F13617470e4d14`
- RitualBountyJudge: `0x8d45b1bad4dD97ADd4BFCf8728aB3d97a387Ee60`

RPC: `https://rpc.ritualfoundation.org` · Explorer: `https://explorer.ritualfoundation.org`
