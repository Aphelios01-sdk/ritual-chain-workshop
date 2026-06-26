"use client";

import { encodePacked, keccak256 } from "viem";

/**
 * Compute a commit-reveal commitment that MUST match the exact formula:
 *   keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
 * @param answer   The plaintext answer (string).
 * @param salt     A 32-byte random hex string (0x-prefixed).
 * @param sender   The participant's address (0x-prefixed).
 * @param bountyId The bounty ID (bigint).
 * @returns        The commitment hash (bytes32, 0x-prefixed hex).
 */
export function computeCommitment(
  answer: string,
  salt: `0x${string}`,
  sender: `0x${string}`,
  bountyId: bigint,
): `0x${string}` {
  return keccak256(
    encodePacked(
      ["string", "bytes32", "address", "uint256"],
      [answer, salt, sender, bountyId],
    ),
  );
}

/**
 * Generate a cryptographically-random 32-byte salt (0x-prefixed hex).
 */
export function generateSalt(): `0x${string}` {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return `0x${Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")}`;
}

/**
 * Persist the (answer, salt) pair for a given (bountyId, participant) so the
 * user can retrieve it later for the reveal phase.
 */
const STORAGE_PREFIX = "commitReveal";

export function saveRevealData(
  bountyId: bigint,
  address: `0x${string}`,
  answer: string,
  salt: `0x${string}`,
): void {
  const key = `${STORAGE_PREFIX}:${bountyId}:${address}`;
  try {
    localStorage.setItem(key, JSON.stringify({ answer, salt }));
  } catch {
    // localStorage unavailable or quota exceeded — silently ignore.
  }
}

export function getRevealData(
  bountyId: bigint,
  address: `0x${string}`,
): { answer: string; salt: `0x${string}` } | null {
  const key = `${STORAGE_PREFIX}:${bountyId}:${address}`;
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    return JSON.parse(raw) as { answer: string; salt: `0x${string}` };
  } catch {
    return null;
  }
}
