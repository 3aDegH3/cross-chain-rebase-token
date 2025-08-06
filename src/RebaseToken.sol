// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/*
 * @title RebaseToken
 * @author Ciara Nightingale
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    /////////////////////
    // Errors
    /////////////////////
    error RebaseToken__InterestRateCanOnlyDecrease(
        uint256 currentInterestRate,
        uint256 newInterestRate
    );

    /////////////////////
    // State Variables
    /////////////////////
    bytes32 private constant MINT_AND_BURN_ROLE =
        keccak256("MINT_AND_BURN_ROLE");
    uint256 private constant PRECISION_FACTOR = 1e18;

    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    /////////////////////
    // Events
    /////////////////////
    event InterestRateSet(uint256 newInterestRate);

    /////////////////////
    // Modifiers
    /////////////////////

    modifier _updateAmountIfMax(address account, uint256 amount) {
        if (amount == type(uint256).max) {
            amount = balanceOf(account);
            require(amount > 0, "Insufficient balance");
        }
        _;
    }

    /////////////////////
    // Constructor
    /////////////////////

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /////////////////////
    // External Functions
    /////////////////////

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(
                s_interestRate,
                _newInterestRate
            );
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /////////////////////
    // Public Functions
    /////////////////////

    /**
     * @notice Mints tokens with user's interest rate context
     * @param _to Recipient of minted tokens
     * @param _value Amount to mint
     * @param _userInterestRate The user's applicable interest rate
     */
    function mint(
        address _to,
        uint256 _value,
        uint256 _userInterestRate
    ) public onlyRole(MINT_AND_BURN_ROLE) {
        s_userInterestRate[_to] = _userInterestRate;
        _mintAccruedInterest(_to);
        _mint(_to, _value);
    }

    /**
     * @notice Returns a user's personalized interest rate
     */
    function getUserInterestRate(address _user) public view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Returns the global interest rate
     */
    function getInterestRate() public view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Returns user balance with accrued interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        uint256 currentPrincipalBalance = super.balanceOf(_user);
        if (currentPrincipalBalance == 0) {
            return 0;
        }
        return
            (currentPrincipalBalance *
                _calculateUserAccumulatedInterestSinceLastUpdate(_user)) /
            PRECISION_FACTOR;
    }

    /**
     * @notice Transfers tokens and mints any accrued interest
     */
    function transfer(
        address to,
        uint256 amount
    ) public override _updateAmountIfMax(msg.sender, amount) returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(to);

        if (
            s_interestRate < s_userInterestRate[to] || super.balanceOf(to) == 0
        ) {
            s_userInterestRate[to] = s_interestRate;
        }

        return super.transfer(to, amount);
    }

    /**
     * @notice Transfers tokens from one user to another and mints accrued interest
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override _updateAmountIfMax(from, amount) returns (bool) {
        _mintAccruedInterest(from);
        _mintAccruedInterest(to);

        if (
            s_interestRate < s_userInterestRate[to] || super.balanceOf(to) == 0
        ) {
            s_userInterestRate[to] = s_interestRate;
        }

        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice Grants the mint and burn role to an address
     */
    function grantMintAndBurnRole(address _address) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _address);
    }

    /////////////////////
    // External View Functions
    /////////////////////

    /**
     * @notice Returns the principal balance of the user (no interest)
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Burns tokens from a user address
     */
    function burn(
        address _from,
        uint256 _amount
    ) external _updateAmountIfMax(_from, _amount) onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /////////////////////
    // Internal & Private Functions
    /////////////////////

    /**
     * @dev Mints any interest that accrued for a user since last update
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_user);

        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        _mint(_user, balanceIncrease);
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
    }

    /**
     * @dev Calculates interest growth since last update
     */

    function _calculateUserAccumulatedInterestSinceLastUpdate(
        address _user
    ) internal view returns (uint256 linearInterest) {
        uint256 timeDifference = block.timestamp -
            s_userLastUpdatedTimestamp[_user];

        linearInterest =
            PRECISION_FACTOR +
            (timeDifference * s_userInterestRate[_user]);
    }
}
