// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRebaseToken {
    // ----------- Events -----------
    event InterestRatetSet(uint256 newInterestRate);

    // ----------- External Functions -----------
    function setInterestRatet(uint256 _newInterestRate) external;

    function burn(address _from, uint256 _amount) external;

    // ----------- Public Functions -----------
    function mint(
        address _to,
        uint256 _value,
        uint256 _userInterestRate
    ) external;

    // ----------- View Functions -----------
    function getUserInterestRate(address _user) external view returns (uint256);

    function getInterestRate() external view returns (uint256);

    function principalBalanceOf(address _user) external view returns (uint256);

    function balanceOf(address _user) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function grantMintAndBurnRole(address _address) external;
}
