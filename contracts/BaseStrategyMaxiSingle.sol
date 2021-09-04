// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./BaseStrategy.sol";
import "./libs/IVaultHealer.sol";

abstract contract BaseStrategyMaxiSingle is BaseStrategy {

    function earn() external override nonReentrant whenNotPaused onlyOwner {
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(addresses.earned).balanceOf(address(this));

        if (earnedAmt > minEarnAmount) {
            earnedAmt = distributeFees(earnedAmt);
    
            if (addresses.earned != addresses.maxi) {
                // Swap all earned to maximized token
                _swap(
                    earnedAmt,
                    paths.earnedToMaxi,
                    address(this)
                );
            }
    
            lastEarnBlock = block.number;
    
            IVaultHealer(owner()).maximizerDeposit(IERC20(addresses.maxi).balanceOf(address(this)));
            _farm();
        }
    }

}