"use client";

import { useState } from "react";
import { useAccount } from "wagmi";
import { contractAddress } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import aiJudgeAbi from "@/abi/AIJudge";
import { computeCommitment, generateSalt, saveRevealData } from "@/lib/commitReveal";
import { useWriteTx } from "@/hooks/useWriteTx";
import { TxStatus } from "@/components/ui";

const explorerBase = ritualChain.blockExplorers?.default.url;

export default function SubmitCommitment({ bountyId }: { bountyId: bigint }) {
  const { address } = useAccount();
  const [answer, setAnswer] = useState("");
  const tx = useWriteTx();

  const handleSubmit = () => {
    if (!address || !contractAddress || !answer.trim()) return;
    const salt = generateSalt();
    const hash = computeCommitment(answer, salt, address, bountyId);
    saveRevealData(bountyId, address, answer, salt);
    tx.run({
      address: contractAddress,
      abi: aiJudgeAbi,
      functionName: "submitCommitment",
      args: [bountyId, hash],
      chainId: ritualChain.id,
    }).catch(() => {});
  };

  return (
    <div className="space-y-2">
      <label className="font-semibold">Submit commitment</label>
      <textarea value={answer} onChange={(e) => setAnswer(e.target.value)} placeholder="Write your answer..." className="textarea-input" rows={3} />
      <button onClick={handleSubmit} disabled={!address || tx.isBusy}>Commit</button>
      <TxStatus state={tx.state} error={tx.error} hash={tx.hash} explorerBase={explorerBase} />
    </div>
  );
}
