// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Vault
 * @notice A vault contract for depositing ETH to mint rebase tokens and redeeming them back to ETH.
 * @author
 */
contract Vault is ReentrancyGuard {
    /////////////////////
    // Errors
    /////////////////////
    error Vault__RedeemFailed();
    error Vault__InsufficientETHInVault();

    /////////////////////
    // State Variables
    /////////////////////
    IRebaseToken private immutable i_rebaseToken;

    /////////////////////
    // Events
    /////////////////////
    /**
     * @notice Emitted when a user deposits ETH and receives rebase tokens
     * @param user The address of the depositor
     * @param amount The amount of ETH deposited
     */
    event Deposit(address indexed user, uint256 indexed amount);

    /**
     * @notice Emitted when a user redeems rebase tokens for ETH
     * @param user The address of the redeemer
     * @param amount The amount of ETH redeemed
     */
    event Redeem(address indexed user, uint256 indexed amount);

    /////////////////////
    // Constructor
    /////////////////////
    /**
     * @param _rebaseToken The address of the RebaseToken contract
     */
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /////////////////////
    // External Functions
    /////////////////////

    /**
     * @notice Allows the contract to receive ETH rewards
     */
    receive() external payable {}

    /**
     * @notice Deposit ETH and mint corresponding rebase tokens
     * @dev Mints tokens by calling the RebaseToken.mint function
     */
    function deposit() external payable nonReentrant {
        require(msg.value > 0, "Vault: deposit amount must be > 0");

        // Mint rebase tokens to the depositor at current interest rate
        i_rebaseToken.mint(
            msg.sender,
            msg.value,
            i_rebaseToken.getInterestRate()
        );

        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeem rebase tokens for ETH
     * @param _amount The amount of rebase tokens to burn and redeem
     */
    function redeem(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Vault: redeem amount must be > 0");

        // Burn the user's rebase tokens
        i_rebaseToken.burn(msg.sender, _amount);

        // Ensure the vault has enough ETH balance
        if (address(this).balance < _amount) {
            revert Vault__InsufficientETHInVault();
        }

        // Transfer ETH back to the user
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }

        emit Redeem(msg.sender, _amount);
    }

    /////////////////////
    // Public View Functions
    /////////////////////

    /**
     * @notice Returns the address of the RebaseToken contract
     */
    function getRebaseToken() public view returns (IRebaseToken) {
        return i_rebaseToken;
    }
}
