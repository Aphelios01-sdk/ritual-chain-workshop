"use client";

import { useState, useEffect } from "react";
import { useAccount } from "wagmi";
import { contractAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import aiJudgeAbi from "@/abi/AIJudge";
import { getRevealData } from "@/lib/commitReveal";
import { useWriteTx } from "@/hooks/useWriteTx";
import { TxStatus } from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

export default function RevealAnswer({ bountyId }: { bountyId: bigint }) {
  const { address } = useAccount();
  const [revealData, setRevealData] = useState<{ answer: string; salt: `0x${string}` } | null>(null);
  const tx = useWriteTx();

  useEffect(() => {
    if (address) setRevealData(getRevealData(bountyId, address));
  }, [bountyId, address]);

  if (!revealData) return <p className="text-sm text-gray-500">No saved commitment data.</p>;

  const handleReveal = () => {
    if (!contractAddress) return;
    tx.run({
      address: contractAddress,
      abi: aiJudgeAbi,
      functionName: "revealAnswer",
      args: [bountyId, revealData.answer, revealData.salt],
      chainId: ritualChain.id,
    }).catch(() => {});
  };

  return (
    <div className="space-y-2">
      <label className="font-semibold">Reveal answer</label>
      <p className="text-xs break-all">Answer: {revealData.answer.slice(0, 80)}...</p>
      <button onClick={handleReveal} disabled={!address || tx.isBusy}>Reveal</button>
      <TxStatus state={tx.state} error={tx.error} hash={tx.hash} explorerBase={explorerBase} />
    </div>
  );
}
