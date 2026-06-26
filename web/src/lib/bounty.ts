import type { Address } from "viem";

/** Parsed shape from getBountyCore + getBountyInfo (BountyJudge v3). */
export type Bounty = {
  owner: Address;
  title: string;
  rubric: string;
  reward: bigint;
  submissionDeadline: bigint;
  revealDeadline: bigint;
  judged: boolean;
  finalized: boolean;
  phase: number;
  participantCount: bigint;
  winnerIndex: bigint;
  aiReview: `0x${string}`;
};

export function parseBounty(
  core: readonly [Address, string, string, bigint, bigint, bigint, boolean, boolean, number],
  info: readonly [bigint, bigint, `0x${string}`],
): Bounty {
  const [owner, title, rubric, reward, sub, rev, judged, finalized, phase] = core;
  const [participantCount, winnerIndex, aiReview] = info;
  return { owner, title, rubric, reward, submissionDeadline: sub, revealDeadline: rev, judged, finalized, phase, participantCount, winnerIndex, aiReview };
}

export type BountyStatus = "submission" | "reveal" | "ready" | "judged" | "finalized";

export function getBountyStatus(b: Bounty, nowSeconds = Date.now() / 1000): BountyStatus {
  if (b.finalized) return "finalized";
  if (b.judged) return "judged";
  if (Number(b.revealDeadline) <= nowSeconds) return "ready";
  if (Number(b.submissionDeadline) <= nowSeconds) return "reveal";
  return "submission";
}

export const STATUS_META: Record<BountyStatus, { label: string; tone: "green" | "amber" | "indigo" | "zinc" }> = {
  submission: { label: "Submission", tone: "green" },
  reveal: { label: "Reveal", tone: "amber" },
  ready: { label: "Ready for judging", tone: "amber" },
  judged: { label: "Judged", tone: "indigo" },
  finalized: { label: "Finalized", tone: "zinc" },
};

export function canSubmit(b: Bounty, nowSeconds = Date.now() / 1000): boolean {
  return !b.judged && !b.finalized && Number(b.submissionDeadline) > nowSeconds;
}
