// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

// For interacting with our own strategy
interface IStrategy {
    // Want address
    function wantAddress() external view returns (address);
    
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Main want token compounding function
    function earn(uint256 _mTokens) external;

    // Transfer want tokens autoFarm -> strategy
    function deposit(uint256 _wantLockedBefore, uint256 _wantAmt) external returns (uint256 tokensAdded);

    // Transfer want tokens strategy -> vaultChef
    function withdraw(uint256 _wantLockedBefore, uint256 _wantAmt) external returns (uint256 tokensRemoved, uint256 tokensToTransfer);
}