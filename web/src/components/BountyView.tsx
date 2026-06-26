"use client";

import { useCallback } from "react";
import { useAccount } from "wagmi";
import { useBounty } from "@/hooks/useBounty";
import { isAddressEqual } from "@/lib/format";
import { decodeAiReview } from "@/lib/aiReview";
import { getBountyStatus } from "@/lib/bounty";
import { BountyDetail } from "@/components/BountyDetail";
import SubmitCommitment from "@/components/SubmitCommitment";
import RevealAnswer from "@/components/RevealAnswer";
import { JudgeAll } from "@/components/JudgeAll";
import { FinalizeWinner } from "@/components/FinalizeWinner";
import { AIReviewDisplay } from "@/components/AIReviewDisplay";
import CommitmentsList from "@/components/CommitmentsList";
import { Card, CardBody, Notice, Spinner } from "@/components/ui";

export function BountyView({ bountyId }: { bountyId: bigint }) {
  const { address } = useAccount();
  const { bounty, isLoading, isError, refetch } = useBounty(bountyId);

  const reload = useCallback(() => { void refetch(); }, [refetch]);

  if (isLoading) return <Card><CardBody><div className="flex items-center gap-2 text-sm text-zinc-400"><Spinner /> Loading bounty #{bountyId.toString()}...</div></CardBody></Card>;
  if (isError || !bounty) return <Notice tone="red">Couldn't load bounty #{bountyId.toString()}.</Notice>;
  if (/^0x0+$/.test(bounty.owner)) return <Notice tone="amber">Bounty #{bountyId.toString()} doesn't exist.</Notice>;

  const isOwner = isAddressEqual(address, bounty.owner);
  const status = getBountyStatus(bounty);

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
      <div className="space-y-4">
        <BountyDetail bountyId={bountyId} bounty={bounty} isOwner={isOwner} />
        {(status === "submission" || status === "reveal") && (
          <SubmitCommitment bountyId={bountyId} />
        )}
        {(status === "reveal") && (
          <RevealAnswer bountyId={bountyId} />
        )}
        {status === "ready" && isOwner && (
          <JudgeAll bountyId={bountyId} bounty={bounty} isOwner={isOwner} onJudged={reload} />
        )}
        {bounty.judged && !bounty.finalized && isOwner && (
          <FinalizeWinner bountyId={bountyId} bounty={bounty} isOwner={isOwner} onFinalized={reload} />
        )}
      </div>
      <div className="space-y-4">
        {bounty.judged && <AIReviewDisplay aiReview={bounty.aiReview} />}
        <CommitmentsList bountyId={bountyId} />
      </div>
    </div>
  );
}
