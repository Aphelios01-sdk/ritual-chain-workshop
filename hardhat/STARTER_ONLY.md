# ⚠️  WORKSHOP STARTER — NOT THE SUBMISSION

This folder contains the **original workshop starter code** (`AIJudge.sol` with
public `submitAnswer` — the flaw the homework fixes). It is kept for reference
and is **NOT part of the graded submission**.

## Where the actual submission lives

👉 **`bounty-judge/`** — the Foundry project with:
- `contracts/BountyJudge.sol` (Track 1: commit-reveal)
- `contracts/RitualBountyJudge.sol` (Track 2: Ritual TEE)
- `test/BountyJudge.t.sol` (77 tests)
- `script/Deploy.s.sol` (deploy to Ritual Chain testnet)

The `contracts/AIJudge.sol` in THIS folder is a convenience copy for grading
(see its header for the canonical source path).

## What the web frontend does

The `web/` folder has been migrated from the original `submitAnswer` flow to
the commit-reveal `BountyJudge` (new components: `SubmitCommitment.tsx`,
`RevealAnswer.tsx`, `CommitmentsList.tsx`; old `submitAnswer` components removed).
