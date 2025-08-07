// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

/**
 * @title ConfigurePoolScript
 * @dev Script to configure cross-chain token pool connections for CCIP bridging
 */
contract ConfigurePoolScript is Script {
    /**
     * @notice Configures a token pool's chain connection settings
     * @dev Sets up the connection between local and remote token pools including rate limiting
     * @param localPool Address of the local TokenPool contract
     * @param remoteChainSelector CCIP chain selector for the remote chain (e.g., Arbitrum = 6101244977088475029)
     * @param remotePool Address of the remote TokenPool contract on destination chain
     * @param remoteToken Address of the token contract on remote chain
     * @param outboundRateLimiterIsEnabled Enable/disable outbound rate limiting
     * @param outboundRateLimiterCapacity Max tokens allowed in outbound window
     * @param outboundRateLimiterRate Tokens replenished per second in outbound
     * @param inboundRateLimiterIsEnabled Enable/disable inbound rate limiting
     * @param inboundRateLimiterCapacity Max tokens allowed in inbound window
     * @param inboundRateLimiterRate Tokens replenished per second in inbound
     */
    function run(
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken,
        bool outboundRateLimiterIsEnabled,
        uint128 outboundRateLimiterCapacity,
        uint128 outboundRateLimiterRate,
        bool inboundRateLimiterIsEnabled,
        uint128 inboundRateLimiterCapacity,
        uint128 inboundRateLimiterRate
    ) public {
        vm.startBroadcast();

        // Prepare remote pool address (ABI encoded for CCIP compatibility)
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);

        // Create chain update configuration with rate limiting
        TokenPool.ChainUpdate[]
            memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: outboundRateLimiterIsEnabled,
                capacity: outboundRateLimiterCapacity,
                rate: outboundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: inboundRateLimiterIsEnabled,
                capacity: inboundRateLimiterCapacity,
                rate: inboundRateLimiterRate
            })
        });

        // Apply configuration (empty array indicates no chains to remove)
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);

        vm.stopBroadcast();
    }
}
