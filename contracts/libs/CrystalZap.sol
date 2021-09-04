// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IUniRouter02.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

//"Zap" functions are for external calls and provide frontrunning protections. "Zip" is for internal contract use
library CrystalZap {
    using Math for uint256;
    
    function zipToLP(address fromToken, uint fromAmount, address router, address[] storage toToken0Path, address[] storage toToken1Path) internal {
        
        require(toToken0Path.length > 0 && toToken1Path.length > 0, "CrystalZap: empty path");
        
        address token0 = toToken0Path[toToken0Path.length - 1];
        address token1 = toToken1Path[toToken1Path.length - 1];
        
        if (fromToken != token0) {
            // Swap half earned to token0
            zip(
                toToken0Path,
                fromAmount / 2,
                router,
                address(this)
            );
        }
        
        if (fromToken != token1) {
            // Swap half earned to token1
            zip(
                toToken1Path,
                fromAmount.ceilDiv(2), // ceilDiv prevents dust from accumulating
                router,
                address(this)
            );
        }

        // Get want tokens, ie. add liquidity
        uint256 token0Amt = IERC20(token0).balanceOf(address(this));
        uint256 token1Amt = IERC20(token1).balanceOf(address(this));
        if (token0Amt > 0 && token1Amt > 0) {
            IUniRouter02(router).addLiquidity(
                token0,
                token1,
                token0Amt,
                token1Amt,
                0,
                0,
                address(this),
                type(uint256).max
            );
        }
    }
    
    function zip(address[] storage _path, uint256 _amountIn, address _router, address _to) internal {
        IUniRouter02(_router).swapExactTokensForTokens(
            _amountIn,
            0,
            _path,
            _to,
            type(uint256).max
        );
    }
    
    function zipMatic(address[] storage _path, uint256 _amountIn, address _router, address _to) internal {
        IUniRouter02(_router).swapExactTokensForETH(
            _amountIn,
            0,
            _path,
            _to,
            type(uint256).max
        );
    }
}