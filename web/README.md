# Bounty Judge — Commit-Reveal Frontend

Frontend for the **Ritual Chain** `BountyJudge` contract (commit-reveal flow).

> Participants submit **commitment hashes** during the submission phase. After the
> deadline, they **reveal** their answers. The bounty owner judges all revealed
> answers via Ritual AI, then finalizes the winner.

Built with **Next.js (App Router) · TypeScript · Tailwind CSS · wagmi · viem**.

---

## Product flow

1. Owner **creates a bounty** with title, rubric, submission deadline, reveal deadline, and reward.
2. Participants **commit** a hash (`keccak256(answer, salt, sender, bountyId)`) during the submission phase.
3. After submission deadline, participants **reveal** their answer + salt.
4. Answers are **hidden** (privacy gate) until the bounty is judged.
5. After the reveal deadline, owner clicks **Judge All** and pastes the LLM prompt.
6. The contract stores/emits the **AI review** + `answersHash`/`inputHash` (auditability).
7. Owner reads the AI review and clicks **Finalize Winner** → reward paid.

---

## Configure

```bash
cp .env.example .env.local
```

| Variable | Purpose |
| --- | --- |
| `NEXT_PUBLIC_CONTRACT_ADDRESS` | Deployed `BountyJudge` address. |
| `NEXT_PUBLIC_RITUAL_RPC_URL` | Ritual Chain JSON-RPC endpoint. |
| `NEXT_PUBLIC_RITUAL_CHAIN_ID` | Numeric chain id (default `1979`). |
| `NEXT_PUBLIC_RITUAL_EXECUTOR_ADDRESS` | LLM executor address (default `0x…0802`). |
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | *(optional)* WalletConnect. |

---

## Run

```bash
pnpm install
pnpm dev              # http://localhost:3000

pnpm build
pnpm start
```

---

## Structure

```
src/
  abi/AIJudge.ts             BountyJudge v3 ABI (39 entries)
  config/
    contract.ts              Address + executor + chain id
    wagmi.ts                 Custom Ritual Chain + wagmi
  app/
    providers.tsx            wagmi + React Query providers
    layout.tsx               Root layout → Providers
    page.tsx                 Dashboard
  hooks/
    useBounty.ts             getBountyCore + getBountyInfo (polls)
    useWriteTx.ts            Tx state machine
    useNow.ts                Clock for countdowns
    useRecentBounties.ts     localStorage history
  lib/
    commitReveal.ts          computeCommitment, generateSalt, localStorage helpers
    ritualLlm.ts             buildJudgeAllLlmInput() encoder
    aiReview.ts              Decode aiReview bytes
    bounty.ts                Bounty type, status (submission/reveal/ready/judged/finalized)
    format.ts                Address/amount/timestamp formatting
  components/
    SubmitCommitment.tsx     Hash + submit commitment
    RevealAnswer.tsx         Read saved (answer, salt) → reveal
    CommitmentsList.tsx      Participant list, show answer only after judged
    JudgeAll.tsx             Manual llmInput + judgeAll()
    FinalizeWinner.tsx       Pick winnerIndex + finalize
    CreateBountyForm.tsx     2 deadlines (submission + reveal)
    BountyDetail.tsx         Phase + 2 countdowns
    BountyView.tsx           Phase-gated rendering
    WalletConnect.tsx        Wallet connection
    ui.tsx                   UI primitives (Card, Button, Input, TxStatus…)
```
