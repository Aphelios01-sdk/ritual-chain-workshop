"use client";

import { useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { parseEther, parseEventLogs } from "viem";
import { contractAddress, isContractConfigured } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import aiJudgeAbi from "@/abi/AIJudge";
import { useWriteTx } from "@/hooks/useWriteTx";
import {
  Card,
  CardHeader,
  CardBody,
  Field,
  Input,
  Textarea,
  Button,
  TxStatus,
  Notice,
} from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

function defaultDeadline(hoursAhead: number): string {
  const d = new Date(Date.now() + hoursAhead * 60 * 60 * 1000);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function CreateBountyForm({ onCreated }: { onCreated?: (bountyId: bigint) => void }) {
  const { isConnected } = useAccount();
  const [title, setTitle] = useState("");
  const [rubric, setRubric] = useState("");
  const [submissionDeadline, setSubmissionDeadline] = useState(defaultDeadline(1));
  const [revealDeadline, setRevealDeadline] = useState(defaultDeadline(3));
  const [reward, setReward] = useState("");
  const [createdId, setCreatedId] = useState<bigint | null>(null);

  const tx = useWriteTx((receipt) => {
    try {
      const logs = parseEventLogs({
        abi: aiJudgeAbi,
        eventName: "BountyCreated",
        logs: receipt.logs,
      }) as unknown as { args?: { bountyId?: bigint } }[];
      const id = logs[0]?.args?.bountyId;
      if (id !== undefined) {
        setCreatedId(id);
        onCreated?.(id);
      }
    } catch { /* not fatal */ }
  });

  const validation = useMemo(() => {
    if (!title.trim()) return "Title is required.";
    if (!rubric.trim()) return "Rubric is required.";
    if (!submissionDeadline) return "Submission deadline is required.";
    if (!revealDeadline) return "Reveal deadline is required.";
    const ts1 = new Date(submissionDeadline).getTime();
    const ts2 = new Date(revealDeadline).getTime();
    if (!Number.isFinite(ts1) || !Number.isFinite(ts2)) return "Invalid deadline.";
    if (ts2 <= ts1) return "Reveal deadline must be after submission.";
    if (reward !== "") {
      try { parseEther(reward); } catch { return "Reward must be a valid number."; }
    }
    return null;
  }, [title, rubric, submissionDeadline, revealDeadline, reward]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (validation || !contractAddress) return;

    const subMs = new Date(submissionDeadline).getTime();
    const revMs = new Date(revealDeadline).getTime();
    if (subMs <= Date.now()) { window.alert("Submission deadline must be in the future."); return; }

    const subTs = BigInt(Math.floor(subMs / 1000));
    const revTs = BigInt(Math.floor(revMs / 1000));
    const value = reward.trim() === "" ? 0n : parseEther(reward.trim());
    setCreatedId(null);

    try {
      await tx.run({
        address: contractAddress,
        abi: aiJudgeAbi,
        functionName: "createBounty",
        args: [title.trim(), rubric.trim(), subTs, revTs],
        value,
        chainId: ritualChain.id,
      });
    } catch { /* surfaced via tx.state */ }
  }

  return (
    <Card>
      <CardHeader title="Create a bounty" subtitle="Fund a reward and define commit-reveal deadlines." />
      <CardBody>
        {!isContractConfigured && (
          <Notice tone="amber">
            Set <code>NEXT_PUBLIC_CONTRACT_ADDRESS</code> in your <code>.env.local</code>.
          </Notice>
        )}
        <form onSubmit={handleSubmit} className="mt-3 space-y-3">
          <Field label="Title">
            <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Best Solidity pattern" maxLength={200} />
          </Field>
          <Field label="Rubric" hint="AI judges against this.">
            <Textarea value={rubric} onChange={(e) => setRubric(e.target.value)} rows={4} placeholder="Correctness 50%, clarity 30%..." />
          </Field>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <Field label="Submission deadline" hint="Commitment phase ends.">
              <Input type="datetime-local" value={submissionDeadline} onChange={(e) => setSubmissionDeadline(e.target.value)} />
            </Field>
            <Field label="Reveal deadline" hint="Reveal window closes here.">
              <Input type="datetime-local" value={revealDeadline} onChange={(e) => setRevealDeadline(e.target.value)} />
            </Field>
          </div>
          <Field label="Reward (RITUAL)" hint="Locked in the contract.">
            <Input type="number" min="0" step="any" value={reward} onChange={(e) => setReward(e.target.value)} placeholder="1.0" />
          </Field>
          {validation && (title || rubric || reward) && <p className="text-xs text-amber-300">{validation}</p>}
          <Button type="submit" disabled={!isConnected || !isContractConfigured || !!validation || tx.isBusy} className="w-full">
            {tx.isBusy ? "Creating…" : "Create bounty"}
          </Button>
          {!isConnected && <p className="text-xs text-zinc-500">Connect wallet to create.</p>}
          <TxStatus state={tx.state} error={tx.error} hash={tx.hash} explorerBase={explorerBase} />
          {createdId !== null && <Notice tone="green">Bounty #{createdId.toString()} created.</Notice>}
        </form>
      </CardBody>
    </Card>
  );
}
