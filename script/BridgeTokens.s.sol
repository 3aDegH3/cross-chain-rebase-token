// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    /// @notice Broadcasts a CCIP token bridge transaction
    /// @param receiver       The address on the destination chain to receive tokens
    /// @param destinationChainSelector  The Chainlink CCIP selector for the target chain
    /// @param tokenToSend    The ERC-20 token address to bridge
    /// @param amount         The amount of tokens to bridge
    /// @param linkToken      The LINK token address used to pay CCIP fees
    /// @param router         The CCIP Router contract address
    function run(
        address receiver,
        uint64 destinationChainSelector,
        address tokenToSend,
        uint256 amount,
        address linkToken,
        address router
    ) public {
        // 1. Prepare the token transfer details in memory
        // 1. Prepare the token transfer details in memory
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: tokenToSend,
            amount: amount
        });

        // 2. Construct the CCIP message payload
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), // encode receiver as bytes
            data: "", // no extra call data
            tokenAmounts: tokenAmounts, // our single-token array
            feeToken: linkToken, // LINK used to pay fee
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // optional CCIP args
        });

        // 3. Query the CCIP fee for this message
        uint256 ccipFee = IRouterClient(router).getFee(
            destinationChainSelector,
            message
        );

        // 4. Begin broadcasting on-chain transactions
        vm.startBroadcast();

        // 4a. Approve LINK for fee payment
        IERC20(linkToken).approve(router, ccipFee);

        // 4b. Approve the router to transfer the specified tokens
        IERC20(tokenToSend).approve(router, amount);

        // 4c. Send the CCIP cross-chain message
        IRouterClient(router).ccipSend(destinationChainSelector, message);

        // 5. End broadcast so further code does not send unintended txs
        vm.stopBroadcast();
    }
}
