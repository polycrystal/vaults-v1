// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./BaseStrategyLP.sol";

abstract contract BaseStrategyLPSingle is BaseStrategyLP {
    using SafeERC20 for IERC20;
    
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
            
            address token0Address = paths.token0ToEarned[0];
            if (earnedAddress != token0Address) {
                // Swap half earned to token0
                _safeSwap(
                    earnedAmt / 2,
                    paths.earnedToToken0,
                    address(this)
                );
            }
            
            address token1Address = paths.token1ToEarned[0];
            if (earnedAddress != token1Address) {
                // Swap half earned to token1
                _safeSwap(
                    earnedAmt / 2,
                    paths.earnedToToken1,
                    address(this)
                );
            }
    
            // Get want tokens, ie. add liquidity
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            if (token0Amt > 0 && token1Amt > 0) {
                IUniRouter02(uniRouterAddress).addLiquidity(
                    token0Address,
                    token1Address,
                    token0Amt,
                    token1Amt,
                    0,
                    0,
                    address(this),
                    block.timestamp + 600
                );
            }
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }
}