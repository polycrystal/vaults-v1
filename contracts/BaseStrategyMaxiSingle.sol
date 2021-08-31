// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./BaseStrategy.sol";
import "./VaultHealerMaxi.sol";

abstract contract BaseStrategyMaxiSingle is BaseStrategy {

    function _vaultHarvest() internal virtual;

    function earn() external override nonReentrant whenNotPaused onlyOwner {
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        if (earnedAmt > 0) {
            earnedAmt = distributeFees(earnedAmt);
            earnedAmt = distributeRewards(earnedAmt);
            earnedAmt = buyBack(earnedAmt);
    
            if (earnedAddress != maxiAddress) {
                // Swap all earned to maximized token
                _safeSwap(
                    earnedAmt,
                    earnedToMaxiPath,
                    address(this)
                );
            }
    
            lastEarnBlock = block.number;
    
            VaultHealerMaxi(vaultChefAddress).maximizerDeposit(IERC20(maxiAddress).balanceOf(address(this)));
            _farm();
        }
    }

}