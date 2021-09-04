// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

enum StratType { BASIC, MASTER_HEALER, MAXIMIZER_CORE, MAXIMIZER }

// For interacting with our own strategy
interface IStrategy {
    // Want address
    function wantAddress() external view returns (address);
    
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    function vaultBalances() external view returns (uint256 wantBalance, uint256 vaultShares);

    // Main want token compounding function
    function earn() external;

    // Transfer want tokens autoFarm -> strategy
    function deposit(address _userAddress, uint256 _wantAmt) external returns (uint256);

    // Transfer want tokens strategy -> vaultChef
    function withdraw(address _userAddress, uint256 _wantAmt) external returns (uint256);
    
    //Maximizer want token (eg crystl)
    function maxiAddress() external returns (address);
    
    function stratType() external returns (StratType);
    
    function initialize(uint _pid, uint _tolerance, address _govAddress, address _masterChef, address _uniRouter, address _wantAddress, address _earnedAddress, address _earnedToWmaticStep) external;

    function initialize(uint _pid, uint _tolerance, address _govAddress, address _masterChef, address _uniRouter, address _wantAddress, address _earnedToWmaticStep) external;
}