// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./BaseStrategy.sol";

abstract contract BaseStrategyLP is BaseStrategy {
    using SafeERC20 for IERC20;

    function convertDustToEarned() external nonReentrant whenNotPaused {
        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        address token0Address = paths.token0ToEarned[0];
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Amt > 0 && token0Address != earnedAddress) {
            // Swap all dust tokens to earned tokens
            _safeSwap(
                token0Amt,
                paths.token0ToEarned,
                address(this)
            );
        }

        // Converts token1 dust (if any) to earned tokens
        address token1Address = paths.token1ToEarned[0];
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Amt > 0 && token1Address != earnedAddress) {
            // Swap all dust tokens to earned tokens
            _safeSwap(
                token1Amt,
                paths.token1ToEarned,
                address(this)
            );
        }
    }
}