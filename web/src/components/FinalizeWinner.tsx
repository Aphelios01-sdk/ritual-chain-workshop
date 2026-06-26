"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import aiJudgeAbi from "@/abi/AIJudge";
import { contractAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import type { Bounty } from "@/lib/bounty";
import { decodeAiReview } from "@/lib/aiReview";
import { useWriteTx } from "@/hooks/useWriteTx";
import { Card, CardHeader, CardBody, Input, Button, TxStatus } from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

export function FinalizeWinner({ bountyId, bounty, isOwner, onFinalized }: { bountyId: bigint; bounty: Bounty; isOwner: boolean; onFinalized: () => void }) {
  const { address } = useAccount();
  const [winnerIndex, setWinnerIndex] = useState("0");
  const tx = useWriteTx(() => onFinalized());

  if (!isOwner || !bounty.judged || bounty.finalized) return null;

  const review = decodeAiReview(bounty.aiReview);

  async function handleFinalize() {
    if (!contractAddress) return;
    try {
      await tx.run({
        address: contractAddress,
        abi: aiJudgeAbi,
        functionName: "finalizeWinner",
        args: [bountyId, BigInt(winnerIndex)],
        chainId: ritualChain.id,
      });
    } catch { /* surfaced */ }
  }

  return (
    <Card>
      <CardHeader title="Finalize winner" subtitle="Pick a winner index (participants array)." />
      <CardBody className="space-y-3">
        {review && (
          <div className="text-xs text-zinc-300 whitespace-pre-wrap max-h-32 overflow-y-auto border rounded p-2">
            <span className="font-semibold">AI review:</span> {review.raw.slice(0, 500)}
          </div>
        )}
        <Input type="number" min="0" value={winnerIndex} onChange={(e) => setWinnerIndex(e.target.value)} placeholder="0" />
        <Button onClick={handleFinalize} disabled={!address || tx.isBusy} className="w-full">
          {tx.isBusy ? "Finalizing…" : "Finalize winner"}
        </Button>
        <TxStatus state={tx.state} error={tx.error} hash={tx.hash} explorerBase={explorerBase} />
      </CardBody>
    </Card>
  );
}
