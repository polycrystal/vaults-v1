// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface IVaultHealer {

    function poolInfo(uint _pid) external view returns (address want, address strat);
    
    function maximizerDeposit(uint _amount) external;
    
    function strategyMaxiCore() external view returns (address);
    function strategyMasterHealer() external view returns (address);
    function strategyMaxiMasterHealer() external view returns (address);
    
}