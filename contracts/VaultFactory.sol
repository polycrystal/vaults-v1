// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./StrategyMaxiCore.sol";
import "./StrategyMaxiMasterHealer.sol";

contract VaultFactory {
 
    function deployMaxiCore(
        address _govAddress,
        address _masterchefAddress, 
        address _uniRouterAddress, 
        uint _pid, 
        address _wantAddress, 
        uint _tolerance, 
        address _earnedToWmaticStep
    ) external returns (address newCoreAddr) {
        StrategyMaxiCore coreStrategy = new StrategyMaxiCore(
            _govAddress,
            msg.sender,
            _masterchefAddress,
            _uniRouterAddress,
            _pid,
            _wantAddress,
            _tolerance,
            _earnedToWmaticStep
        );
        return address(coreStrategy);    
    }
    
    function deployMaxiMasterHealer(
        address _govAddress,    
        address _masterChef,
        address _uniRouter,
        address _want,
        address _earned,
        address _maxi,
        uint256 _pid,
        uint256 _tolerance,
        address _earnedToWmaticStep //address(0) if swapping earned->wmatic directly, or the address of an intermediate trade token such as weth
    ) external returns (address newMaxiAddr) {
        StrategyMaxiMasterHealer newStrat = new StrategyMaxiMasterHealer (
            _govAddress,
            msg.sender,
            _masterChef,
            _uniRouter,
            _want,
            _earned,
            _maxi,
            _pid,
            _tolerance,
            _earnedToWmaticStep
        );
        return address(newStrat);
    }
    
   
}