// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./BaseStrategy.sol";
import "./libs/CrystalZap.sol";

abstract contract BaseStrategyLPSingle is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;
    
    function earn() external override nonReentrant whenNotPaused onlyOwner {
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(addresses.earned).balanceOf(address(this));

        if (earnedAmt > minEarnAmount) {
            earnedAmt = distributeFees(earnedAmt);
            
            CrystalZap.zipToLP(addresses.earned, earnedAmt, addresses.token0, addresses.token1);
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }
}