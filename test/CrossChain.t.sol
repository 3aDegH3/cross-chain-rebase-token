// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console, Test} from "forge-std/Test.sol";

// Import CCIP related contracts
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

// Import project specific contracts
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

/**
 * @title CrossChainTest
 * @dev Test contract for cross-chain rebase token functionality using CCIP
 */
contract CrossChainTest is Test {
    // Test accounts
    address public owner = makeAddr("owner");
    address alice = makeAddr("alice");

    // CCIP simulator and test configuration
    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;
    uint256 public SEND_VALUE = 1e5; // Default test amount

    // Chain forks for testing
    uint256 sepoliaFork; // Source chain (Ethereum)
    uint256 arbSepoliaFork; // Destination chain (Arbitrum)

    // Token and pool instances
    RebaseToken destRebaseToken; // Token on destination chain
    RebaseToken sourceRebaseToken; // Token on source chain
    RebaseTokenPool destPool; // Pool on destination chain
    RebaseTokenPool sourcePool; // Pool on source chain

    // Registry and admin contracts
    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryarbSepolia;
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;
    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerCustomarbSepolia;

    // Vault contract for staking
    Vault vault;

    /**
     * @dev Setup the test environment
     * - Creates forks of Sepolia and Arbitrum
     * - Deploys contracts on both chains
     * - Configures token permissions and admin roles
     */
    function setUp() public {
        address[] memory allowlist = new address[](0); // Empty allowlist

        // 1. Setup chain forks for testing
        sepoliaFork = vm.createSelectFork("eth"); // Source chain (Sepolia)
        arbSepoliaFork = vm.createFork("arb"); // Destination chain (Arbitrum)

        // Initialize CCIP local simulator
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 2. Deploy and configure on source chain (Sepolia)
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );

        vm.startPrank(owner);
        // Deploy source token and pool
        sourceRebaseToken = new RebaseToken();
        console.log("Source rebase token address:", address(sourceRebaseToken));

        sourcePool = new RebaseTokenPool(
            IERC20(address(sourceRebaseToken)),
            allowlist,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        // Deploy vault and fund it
        vault = new Vault(IRebaseToken(address(sourceRebaseToken)));
        vm.deal(address(vault), 1e18); // Fund vault with 1 ETH

        // Configure token permissions
        sourceRebaseToken.grantMintAndBurnRole(address(sourcePool));
        sourceRebaseToken.grantMintAndBurnRole(address(vault));

        // Setup admin roles
        registryModuleOwnerCustomSepolia = RegistryModuleOwnerCustom(
            sepoliaNetworkDetails.registryModuleOwnerCustomAddress
        );
        registryModuleOwnerCustomSepolia.registerAdminViaOwner(
            address(sourceRebaseToken)
        );

        tokenAdminRegistrySepolia = TokenAdminRegistry(
            sepoliaNetworkDetails.tokenAdminRegistryAddress
        );
        tokenAdminRegistrySepolia.acceptAdminRole(address(sourceRebaseToken));
        tokenAdminRegistrySepolia.setPool(
            address(sourceRebaseToken),
            address(sourcePool)
        );

        vm.stopPrank();

        // 3. Deploy and configure on destination chain (Arbitrum)
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);

        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );

        // Deploy destination token and pool
        destRebaseToken = new RebaseToken();
        console.log(
            "Destination rebase token address:",
            address(destRebaseToken)
        );

        destPool = new RebaseTokenPool(
            IERC20(address(destRebaseToken)),
            allowlist,
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        // Configure token permissions
        destRebaseToken.grantMintAndBurnRole(address(destPool));

        // Setup admin roles
        registryModuleOwnerCustomarbSepolia = RegistryModuleOwnerCustom(
            arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress
        );
        registryModuleOwnerCustomarbSepolia.registerAdminViaOwner(
            address(destRebaseToken)
        );

        tokenAdminRegistryarbSepolia = TokenAdminRegistry(
            arbSepoliaNetworkDetails.tokenAdminRegistryAddress
        );
        tokenAdminRegistryarbSepolia.acceptAdminRole(address(destRebaseToken));
        tokenAdminRegistryarbSepolia.setPool(
            address(destRebaseToken),
            address(destPool)
        );

        vm.stopPrank();
    }

    /**
     * @dev Configure token pool connections between chains
     * @param fork The fork to configure (source or destination)
     * @param localPool The local token pool
     * @param remotePool The remote token pool
     * @param remoteToken The remote token address
     * @param remoteNetworkDetails Network details of the remote chain
     */
    function configureTokenPool(
        uint256 fork,
        TokenPool localPool,
        TokenPool remotePool,
        IRebaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);

        // Create chain update configuration
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(address(remotePool));

        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });

        // Apply chain updates (empty array for chains to remove)
        uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);
        localPool.applyChainUpdates(remoteChainSelectorsToRemove, chains);

        vm.stopPrank();
    }

    /**
     * @dev Test function to bridge tokens between chains
     * @param amountToBridge Amount of tokens to bridge
     * @param localFork Source chain fork
     * @param remoteFork Destination chain fork
     * @param localNetworkDetails Source chain network details
     * @param remoteNetworkDetails Destination chain network details
     * @param localToken Source chain token
     * @param remoteToken Destination chain token
     */
    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // 1. Prepare and send CCIP message on source chain
        vm.selectFork(localFork);
        vm.startPrank(alice);

        // Create token transfer details
        Client.EVMTokenAmount[]
            memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        tokenToSendDetails[0] = Client.EVMTokenAmount({
            token: address(localToken),
            amount: amountToBridge
        });

        // Approve token transfer
        IERC20(address(localToken)).approve(
            localNetworkDetails.routerAddress,
            amountToBridge
        );

        // Create CCIP message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(alice), // Encoded receiver address
            data: "", // No additional data
            tokenAmounts: tokenToSendDetails, // Tokens to transfer
            extraArgs: "", // No extra arguments
            feeToken: localNetworkDetails.linkAddress // Pay fees with LINK
        });

        vm.stopPrank();

        // 2. Fund user with LINK for fees
        uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(
            remoteNetworkDetails.chainSelector,
            message
        );
        ccipLocalSimulatorFork.requestLinkFromFaucet(alice, fee);

        // 3. Execute the bridge transfer
        vm.startPrank(alice);
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            fee
        );

        // Log balances before bridging
        uint256 balanceBeforeBridge = localToken.balanceOf(alice);
        console.log("Local balance before bridge:", balanceBeforeBridge);

        // Send CCIP message
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(
            remoteNetworkDetails.chainSelector,
            message
        );

        // Verify source chain balance after
        uint256 sourceBalanceAfterBridge = localToken.balanceOf(alice);
        console.log("Local balance after bridge:", sourceBalanceAfterBridge);
        assertEq(
            sourceBalanceAfterBridge,
            balanceBeforeBridge - amountToBridge
        );

        vm.stopPrank();

        // 4. Process the message on destination chain
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 900); // Simulate 15min bridge time

        // Log initial destination balance
        uint256 initialArbBalance = remoteToken.balanceOf(alice);
        console.log("Remote balance before bridge:", initialArbBalance);

        // Route the message (must be called from source chain)
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // Verify destination chain balance after
        uint256 destBalance = remoteToken.balanceOf(alice);
        console.log("Remote balance after bridge:", destBalance);
        console.log(
            "Remote user interest rate:",
            remoteToken.getUserInterestRate(alice)
        );
        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    //////////////////////
    //      Tests       //
    //////////////////////

    function testBridgeAllTokens() public {
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork,
            destPool,
            sourcePool,
            IRebaseToken(address(sourceRebaseToken)),
            sepoliaNetworkDetails
        );
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(alice, SEND_VALUE);
        vm.startPrank(alice);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // bridge the tokens
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(
            alice
        );
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();
        // bridge ALL TOKENS to the destination chain
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
    }

    function testBridgeAllTokensBack() public {
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork,
            destPool,
            sourcePool,
            IRebaseToken(address(sourceRebaseToken)),
            sepoliaNetworkDetails
        );
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(alice, SEND_VALUE);
        vm.startPrank(alice);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        // bridge the tokens
        console.log("Bridging %d tokens", SEND_VALUE);
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(
            alice
        );
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();
        // bridge ALL TOKENS to the destination chain
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
        // bridge back ALL TOKENS to the source chain after 1 hour
        vm.selectFork(arbSepoliaFork);
        console.log(
            "User Balance Before Warp: %d",
            destRebaseToken.balanceOf(alice)
        );
        vm.warp(block.timestamp + 3600);
        console.log(
            "User Balance After Warp: %d",
            destRebaseToken.balanceOf(alice)
        );
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(alice);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }

    function testBridgeTwice() public {
        configureTokenPool(
            sepoliaFork,
            sourcePool,
            destPool,
            IRebaseToken(address(destRebaseToken)),
            arbSepoliaNetworkDetails
        );
        configureTokenPool(
            arbSepoliaFork,
            destPool,
            sourcePool,
            IRebaseToken(address(sourceRebaseToken)),
            sepoliaNetworkDetails
        );
        // We are working on the source chain (Sepolia)
        vm.selectFork(sepoliaFork);
        // Pretend a user is interacting with the protocol
        // Give the user some ETH
        vm.deal(alice, SEND_VALUE);
        vm.startPrank(alice);
        // Deposit to the vault and receive tokens
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        uint256 startBalance = IERC20(address(sourceRebaseToken)).balanceOf(
            alice
        );
        assertEq(startBalance, SEND_VALUE);
        vm.stopPrank();
        // bridge half tokens to the destination chain
        // bridge the tokens
        console.log(
            "Bridging %d tokens (first bridging event)",
            SEND_VALUE / 2
        );
        bridgeTokens(
            SEND_VALUE / 2,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
        // wait 1 hour for the interest to accrue
        vm.selectFork(sepoliaFork);
        vm.warp(block.timestamp + 3600);
        uint256 newSourceBalance = IERC20(address(sourceRebaseToken)).balanceOf(
            alice
        );
        // bridge the tokens
        console.log(
            "Bridging %d tokens (second bridging event)",
            newSourceBalance
        );
        bridgeTokens(
            newSourceBalance,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sourceRebaseToken,
            destRebaseToken
        );
        // bridge back ALL TOKENS to the source chain after 1 hour
        vm.selectFork(arbSepoliaFork);
        // wait an hour for the tokens to accrue interest on the destination chain
        console.log(
            "User Balance Before Warp: %d",
            destRebaseToken.balanceOf(alice)
        );
        vm.warp(block.timestamp + 3600);
        console.log(
            "User Balance After Warp: %d",
            destRebaseToken.balanceOf(alice)
        );
        uint256 destBalance = IERC20(address(destRebaseToken)).balanceOf(alice);
        console.log("Amount bridging back %d tokens ", destBalance);
        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            destRebaseToken,
            sourceRebaseToken
        );
    }
}
