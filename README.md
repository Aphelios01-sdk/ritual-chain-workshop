# Ritual Academy Bootcamp #1 — Homework Submission

Fork of [cozfuttu/ritual-chain-workshop](https://github.com/cozfuttu/ritual-chain-workshop).

## Repository layout

| Directory | What it is |
|---|---|
| **`bounty-judge/`** | **Homework submission** — Foundry project with the commit-reveal `BountyJudge` (Track 1), Ritual TEE `RitualBountyJudge` (Track 2), 79 tests, deploy script. See [`bounty-judge/README.md`](./bounty-judge/README.md). |
| `web/` | Frontend migrated to commit-reveal (SubmitCommitment, RevealAnswer, CommitmentsList). Uses ABI + address from `bounty-judge/`. |

## Quick start

```bash
# Run the homework test suite
cd bounty-judge
forge test                   # 79/79 passing

# Deploy to Ritual Chain testnet
cp .env.example .env         # set RITUAL_RPC_URL + DEPLOYER_PRIVATE_KEY
forge script script/Deploy.s.sol --rpc-url ritual --broadcast
```

## Deployed (Ritual testnet, chainId 1979)

- BountyJudge: `0x8825681a0472Bdc7e547f36dc7292DCE9449c131`
- RitualBountyJudge: `0xeb231C16A108A35d11C583BA3440dBa37f9A2596`

RPC: `https://rpc.ritualfoundation.org` · Explorer: `https://explorer.ritualfoundation.org`
