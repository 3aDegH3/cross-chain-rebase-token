// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Import Chainlink CCIP TokenPool base contract
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
// Import Pool library (defines structs for LockOrBurn and ReleaseOrMint operations)
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
// Import ERC20 interface
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
// Import custom RebaseToken interface
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    /**
     * @notice Constructor to initialize the RebaseTokenPool
     * @param _token The ERC20 token handled by this pool
     * @param _allowlist List of addresses allowed to use the pool
     * @param _rmnProxy Address of the RMN (Risk Management Network) proxy
     * @param _router Address of the CCIP router
     */
    constructor(
        IERC20 _token,
        address[] memory _allowlist,
        address _rmnProxy,
        address _router
    )
        TokenPool(
            _token, // ERC20 token for this pool
            18, // Token decimals (assumed 18)
            _allowlist, // Allowlist of addresses
            _rmnProxy, // RMN proxy
            _router // CCIP Router
        )
    {}

    /**
     * @notice Locks or burns tokens on the source chain for cross-chain transfer
     * @dev This function will:
     *      1. Validate the request
     *      2. Get the user's current interest rate (specific to RebaseToken logic)
     *      3. Burn the tokens from the pool
     *      4. Return metadata for the destination chain pool
     * @param lockOrBurnIn Struct containing cross-chain transfer details
     * @return lockOrBurnOut Struct containing destination token address and pool data
     */
    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) external override returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut) {
        // Step 1: Validate the request (checks token, RMN curse, allowlist, etc.)
        _validateLockOrBurn(lockOrBurnIn);

        // Step 2: Retrieve the user's interest rate before burning (to send to destination chain)
        uint256 userInterestRate = IRebaseToken(address(i_token))
            .getUserInterestRate(lockOrBurnIn.originalSender);

        // Step 3: Burn the tokens from this pool's balance
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        // Step 4: Prepare data for the destination chain
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            // Destination token address on the remote chain
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            // Encoded user interest rate to be passed to the destination pool
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /// @notice Mints the tokens on the destination chain
    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) external returns (Pool.ReleaseOrMintOutV1 memory) {
        // Validate the incoming release or mint request
        _validateReleaseOrMint(releaseOrMintIn);

        address receiver = releaseOrMintIn.receiver;

        // Decode the user interest rate sent from the source chain
        uint256 userInterestRate = abi.decode(
            releaseOrMintIn.sourcePoolData,
            (uint256)
        );

        // Mint rebasing tokens to the receiver on the destination chain
        // This also accounts for accrued interest
        IRebaseToken(address(i_token)).mint(
            receiver,
            releaseOrMintIn.amount,
            userInterestRate
        );

        // Return the minted amount as confirmation
        return
            Pool.ReleaseOrMintOutV1({
                destinationAmount: releaseOrMintIn.amount
            });
    }
}
