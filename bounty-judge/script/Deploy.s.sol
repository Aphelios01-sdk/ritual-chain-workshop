// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {BountyJudge} from "../contracts/BountyJudge.sol";
import {RitualBountyJudge} from "../contracts/RitualBountyJudge.sol";

/// @notice  Deploys the homework contracts to Ritual Chain (chainId 1979).
///          Ritual's LLM inference precompile lives at 0x0802, so BountyJudge
///          is constructed with that address — making judgeAll() fully
///          functional (unlike a Base mainnet deployment).
///
/// @dev     forge script script/Deploy.s.sol \
///            --rpc-url ritual \
///            --private-key $DEPLOYER_PRIVATE_KEY \
///            --broadcast \
///            --verify
contract Deploy is Script {
    // Ritual Chain LLM inference precompile (short-running async).
    // Same address the test suite mocks via vm.etch(0x0802, ...).
    address constant RITUAL_LLM_PRECOMPILE = 0x0000000000000000000000000000000000000802;

    function run() external returns (BountyJudge bounty, RitualBountyJudge ritualBounty) {
        // Broadcast as the sender supplied via --private-key / --sender.
        vm.startBroadcast();

        // Track 1 — Commit-Reveal Bounty Judge (precompile configurable).
        bounty = new BountyJudge(RITUAL_LLM_PRECOMPILE);

        // Track 2 — Ritual-native encrypted submissions + TEE attestation.
        ritualBounty = new RitualBountyJudge();

        vm.stopBroadcast();

        console2.log("Deployer (msg.sender): ", msg.sender);
        console2.log("BountyJudge        @ ", address(bounty));
        console2.log("RitualBountyJudge  @ ", address(ritualBounty));
        console2.log("LLM precompile     @ ", RITUAL_LLM_PRECOMPILE);
    }
}
