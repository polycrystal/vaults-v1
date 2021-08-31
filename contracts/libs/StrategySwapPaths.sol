// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

library StrategySwapPaths {
    
    address internal constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address internal constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    
    function makeEarnedToWmaticPath(address earnedAddress, address middleStep) internal pure returns (address[] memory earnedToWmaticPath) {
        if (earnedAddress == WMATIC) {
            earnedToWmaticPath = new address[](1);
            earnedToWmaticPath[0] = WMATIC;
        } else if (middleStep == address(0)) {
            earnedToWmaticPath = new address[](2);
            earnedToWmaticPath[0] = earnedAddress;
            earnedToWmaticPath[1] = WMATIC;
        } else {
            earnedToWmaticPath = new address[](3);
            earnedToWmaticPath[0] = earnedAddress;
            earnedToWmaticPath[1] = middleStep;
            earnedToWmaticPath[2] = WMATIC;
        }
    }
    function makeEarnedToXPath(address[] memory earnedToWmaticPath, address xToken) internal pure returns (address[] memory earnedToXPath) {
        
        if (earnedToWmaticPath[0] == xToken) {
            earnedToXPath = new address[](1);
            earnedToXPath[0] = xToken;
        } else if (earnedToWmaticPath[1] == USDC) {
            earnedToXPath = new address[](2);
            earnedToXPath[0] = earnedToWmaticPath[0];
            earnedToXPath[1] = xToken;
        } else {
            earnedToXPath = new address[](earnedToWmaticPath.length + 1);
            for (uint i; i < earnedToWmaticPath.length; i++) {
                earnedToXPath[i] = earnedToWmaticPath[i];
            }
            earnedToXPath[earnedToWmaticPath.length] = xToken;
        }
    }
    
}