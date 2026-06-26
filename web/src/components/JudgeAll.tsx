"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import aiJudgeAbi from "@/abi/AIJudge";
import { contractAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import type { Bounty } from "@/lib/bounty";
import { useWriteTx } from "@/hooks/useWriteTx";
import { Card, CardHeader, CardBody, Textarea, Button, TxStatus, Notice } from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

export function JudgeAll({ bountyId, bounty, isOwner, onJudged }: { bountyId: bigint; bounty: Bounty; isOwner: boolean; onJudged: () => void }) {
  const { address } = useAccount();
  const [prompt, setPrompt] = useState("");
  const tx = useWriteTx(() => onJudged());

  if (!isOwner || bounty.judged || bounty.finalized || bounty.participantCount === 0n) return null;

  async function handleJudge() {
    if (!contractAddress || !prompt.trim()) return;
    const llmInput = `0x${Buffer.from(prompt).toString("hex")}` as `0x${string}`;
    try {
      await tx.run({
        address: contractAddress,
        abi: aiJudgeAbi,
        functionName: "judgeAll",
        args: [bountyId, llmInput],
        chainId: ritualChain.id,
      });
    } catch { /* surfaced */ }
  }

  return (
    <Card>
      <CardHeader title="Judge all" subtitle="Paste the full LLM prompt (rubric + revealed answers) as raw text." />
      <CardBody className="space-y-3">
        {!address && <Notice tone="amber">Connect wallet to judge.</Notice>}
        <Textarea value={prompt} onChange={(e) => setPrompt(e.target.value)} rows={6} placeholder="Rubric + submissions..." />
        <Button onClick={handleJudge} disabled={!address || tx.isBusy || !prompt.trim()} className="w-full">
          {tx.isBusy ? "Judging…" : "Judge all"}
        </Button>
        <TxStatus state={tx.state} error={tx.error} hash={tx.hash} explorerBase={explorerBase} />
      </CardBody>
    </Card>
  );
}
