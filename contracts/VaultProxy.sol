// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/proxy/Proxy.sol";

import "./libs/IVaultHealer.sol";
import "./libs/IStrategy.sol";

contract VaultProxy is Proxy {

    IVaultHealer internal __vaultHealer;
    StratType internal __stratType;
    
    constructor(StratType _stratType) {
        require(_stratType != StratType.BASIC, "YA BASIC");
        __stratType = _stratType;
        __vaultHealer = IVaultHealer(msg.sender);
    }
    
    function _implementation() internal view override returns (address) {
        if (__stratType == StratType.MASTER_HEALER) return __vaultHealer.strategyMasterHealer();
        if (__stratType == StratType.MAXIMIZER_CORE) return __vaultHealer.strategyMaxiCore();
        if (__stratType == StratType.MAXIMIZER) return __vaultHealer.strategyMaxiMasterHealer();
        revert("No implementation");
    }
}