"use client";

import { useReadContract } from "wagmi";
import aiJudgeAbi from "@/abi/AIJudge";
import { contractAddress, isContractConfigured } from "@/config/contract";
import { ritualChain } from "@/config/wagmi";
import { parseBounty, type Bounty } from "@/lib/bounty";

export function useBounty(bountyId?: bigint) {
  const enabled = bountyId !== undefined && isContractConfigured;

  const core = useReadContract({
    address: contractAddress,
    abi: aiJudgeAbi,
    functionName: "getBountyCore",
    args: bountyId !== undefined ? [bountyId] : undefined,
    chainId: ritualChain.id,
    query: { enabled, refetchInterval: 12_000 },
  });

  const info = useReadContract({
    address: contractAddress,
    abi: aiJudgeAbi,
    functionName: "getBountyInfo",
    args: bountyId !== undefined ? [bountyId] : undefined,
    chainId: ritualChain.id,
    query: { enabled, refetchInterval: 12_000 },
  });

  const bounty: Bounty | undefined =
    core.data && info.data ? parseBounty(core.data as Parameters<typeof parseBounty>[0], info.data as Parameters<typeof parseBounty>[1]) : undefined;

  return {
    bounty,
    isLoading: core.isLoading || info.isLoading,
    isError: core.isError || info.isError,
    error: core.error || info.error,
    refetch: () => { core.refetch(); info.refetch(); },
  };
}
