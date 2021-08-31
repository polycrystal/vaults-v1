// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface IVaultHealer {

    function poolInfo(uint _pid) external view returns (address want, address strat);
    
    function maximizerDeposit(uint _amount) external;
}