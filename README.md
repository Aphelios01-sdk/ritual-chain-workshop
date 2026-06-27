# Ritual Academy Bootcamp #1 — Homework Submission

Fork of [cozfuttu/ritual-chain-workshop](https://github.com/cozfuttu/ritual-chain-workshop).

## Repository layout

| Directory | What it is |
|---|---|
| **`bounty-judge/`** | **Homework submission** — Foundry project with the commit-reveal `BountyJudge` (Track 1), Ritual TEE `RitualBountyJudge` (Track 2), 65 tests, and deploy script. See [`bounty-judge/README.md`](./bounty-judge/README.md) for the full lifecycle, architecture comparison, and reflection. |
| `hardhat/` | Original workshop starter. Contains the unmodified `AIJudge.sol` (public submissions — the flaw we fix in the homework). Not used by the submission. |
| `web/` | Workshop frontend — migrated to the commit-reveal `BountyJudge` (SubmitCommitment, RevealAnswer, CommitmentsList). Uses the new ABI and contract address from `bounty-judge/`. |

## Quick start

```bash
# Run the homework test suite
cd bounty-judge
forge test                   # 65/65 passing

# Deploy to Ritual Chain testnet
cp .env.example .env         # set RITUAL_RPC_URL + DEPLOYER_PRIVATE_KEY
forge script script/Deploy.s.sol --rpc-url ritual --broadcast
```

## Deployed (Ritual testnet, chainId 1979)

- BountyJudge: `0xcBd6a1742a1f15309B3458F47aFBcCfb1CA8da99`
- RitualBountyJudge: `0x3D9C52CeaA5988eF8289955ECdE65F86B1Ae2b2C`

RPC: `https://rpc.ritualfoundation.org` · Explorer: `https://explorer.ritualfoundation.org`
