// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

/**
 * @title TokenAndPoolDeployer
 * @dev Deployment script for RebaseToken and its associated TokenPool with CCIP configuration
 */
contract TokenAndPoolDeployer is Script {
    /**
     * @notice Deploys and configures a new RebaseToken with its TokenPool
     * @return token The deployed RebaseToken contract
     * @return pool The deployed RebaseTokenPool contract
     * @dev Performs the following actions:
     * 1. Initializes CCIP local simulator
     * 2. Deploys new RebaseToken
     * 3. Deploys TokenPool connected to the token
     * 4. Configures mint/burn permissions
     * 5. Sets up admin roles in TokenAdminRegistry
     */
    function run() public returns (RebaseToken token, RebaseTokenPool pool) {
        // Initialize CCIP local simulator and get network details
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork
            .getNetworkDetails(block.chainid);

        vm.startBroadcast();

        // Deploy RebaseToken contract
        token = new RebaseToken();

        // Deploy TokenPool with CCIP configuration
        pool = new RebaseTokenPool(
            IERC20(address(token)), // Token address
            new address[](0), // Empty allowlist
            networkDetails.rmnProxyAddress, // CCIP Risk Management Network proxy
            networkDetails.routerAddress // CCIP Router address
        );

        // Configure token permissions
        token.grantMintAndBurnRole(address(pool));

        // Set up admin roles in CCIP registry
        RegistryModuleOwnerCustom(
            networkDetails.registryModuleOwnerCustomAddress
        ).registerAdminViaOwner(address(token));

        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(token));

        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(
            address(token),
            address(pool)
        );

        vm.stopBroadcast();
    }
}

/**
 * @title DeployerVault
 * @dev Deployment script for Vault contract that works with RebaseToken
 */
contract DeployerVault is Script {
    /**
     * @notice Deploys a new Vault contract
     * @param _rebaseToken Address of the RebaseToken contract
     * @return vault The deployed Vault contract
     * @dev Performs:
     * 1. Vault deployment with token reference
     * 2. Configures mint/burn permissions for the vault
     */
    function run(address _rebaseToken) public returns (Vault vault) {
        vm.startBroadcast();

        // Deploy Vault connected to RebaseToken
        vault = new Vault(IRebaseToken(_rebaseToken));

        // Grant vault mint/burn permissions on token
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));

        vm.stopBroadcast();
    }
}
