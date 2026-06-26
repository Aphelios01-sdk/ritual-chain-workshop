"use client";

import { useState, useEffect } from "react";
import { useReadContract } from "wagmi";
import { config } from "@/config/wagmi";
import { contractAddress } from "@/config/contract";
import aiJudgeAbi from "@/abi/AIJudge";

export default function CommitmentsList({ bountyId }: { bountyId: bigint }) {
  const [participants, setParticipants] = useState<`0x${string}`[]>([]);

  const { data: bountyCore } = useReadContract({
    abi: aiJudgeAbi,
    address: contractAddress,
    functionName: "getBountyCore",
    args: [bountyId],
    config,
    query: { enabled: Boolean(contractAddress) },
  });

  const judged: boolean = bountyCore ? (bountyCore as [unknown, unknown, unknown, unknown, unknown, unknown, boolean, boolean, number])[6] : false;

  const { data: parts } = useReadContract({
    abi: aiJudgeAbi,
    address: contractAddress,
    functionName: "getParticipants",
    args: [bountyId],
    config,
    query: { enabled: Boolean(contractAddress) },
  });

  useEffect(() => {
    if (parts) setParticipants(parts as `0x${string}`[]);
  }, [parts]);

  return (
    <div className="space-y-1">
      {participants.map((p, i) => (
        <SubmissionRow key={p} bountyId={bountyId} participant={p} index={i} judged={judged} />
      ))}
    </div>
  );
}

function SubmissionRow({
  bountyId,
  participant,
  index,
  judged,
}: {
  bountyId: bigint;
  participant: `0x${string}`;
  index: number;
  judged: boolean;
}) {
  const { data: sub } = useReadContract({
    abi: aiJudgeAbi,
    address: contractAddress,
    functionName: "getSubmission",
    args: [bountyId, participant],
    config,
    query: { enabled: Boolean(contractAddress) },
  });

  const [commitment, answer, revealed] = sub
    ? (sub as readonly [`0x${string}`, string, boolean])
    : ["0x" as `0x${string}`, "", false];

  return (
    <div className="text-sm border rounded p-2">
      <p>#{index + 1} <span className="font-mono text-xs">{participant.slice(0, 10)}...</span></p>
      <p>
        Status:{" "}
        {revealed ? (
          <span className="text-green-500">revealed</span>
        ) : commitment !== "0x0000000000000000000000000000000000000000000000000000000000000000" ? (
          <span className="text-yellow-500">committed</span>
        ) : (
          <span className="text-gray-400">—</span>
        )}
      </p>
      <p className="text-xs font-mono break-all">Hash: {commitment}</p>
      {judged && revealed ? (
        <p className="text-xs mt-1">Answer: {answer}</p>
      ) : revealed ? (
        <p className="text-xs mt-1 text-gray-400">Answer hidden until judging completes</p>
      ) : null}
    </div>
  );
}
