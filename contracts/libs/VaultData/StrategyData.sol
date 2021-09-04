// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "../IStrategy.sol";
import "../IUniPair.sol";
import "../IUniRouter02.sol";
import "../IVaultHealer.sol";
import "../IMasterchef.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library StrategyData {
    
    struct StratData {
        bytes32 SID;
        bytes32 MID[];
        
        uint cSharesTotal;
        uint mSharesTotal;
        uint mTokensTotal;
        mapping (address => uint) cSharesUser;
        Maximizer[] m;
    }
    
    struct Chef {
        IMasterchef masterChef;
        address reward;
        uint16 pid;
        uint16 depositFee; //10000 = 100%
        uint16 depositFeeMax; // usually, these vaults 
        uint8 risk; // 0 = safu, 3 = risky
    }
    
    struct User {
        uint cShares;
        uint mShares;
        uint[] mPoolShares[];
        uint[4]] toleranceDistribution; //for risk management
    }
    
    //standard primary lp->lp
    struct Compounder {
        uint256 sharesTotal;
        
        address[] earnedToToken0;
        address[] earnedToToken1;
    }
    
    struct Tokens {
        IUniPair want;
        IERC20 earned;
        IERC20 token0;
        IERC20 token1;
    }
    struct feePaths {
        address[] earnedToWmatic;
        address[] earnedToCrystl;
        address[] earnedToMaxi;
    }    
    struct Addresses {
        address gov;
        IUniRouter02 router;
        IMasterchef masterChef;
    }
    
    struct Balances {
        uint256 cSharesTotal;
        uint256 mTokensGrandTotal;
        uint256[] mTokenTotals;
    }
    

    
    struct Maximizer {
        uint256 sharesTotal;
        mapping (address => uint) userShares;
        address strategy;
        address[] earnedToMaxiPath;
    }
    
    function calcSID(address want, )
    
    IERC20 public constant USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IERC20 public constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 public constant CRYSTL = IERC20(0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64);
    
    //isLPStrategy should be true if the strategy compounds to LP
    function buildAllPaths(Tokens storage tokens, Paths storage paths, address middleStep, bool isLPStrategy) internal {
            
        makeEarnedToWmaticPath(tokens, paths, middleStep);
        makeEarnedToXPath(paths.earnedToUsdc, paths.earnedToWmatic, USDC);
        makeEarnedToXPath(paths.earnedToCrystl, paths.earnedToWmatic, CRYSTL);
        
        if (address(tokens.maxi) != address(0)) makeEarnedToXPath(paths.earnedToMaxi, paths.earnedToWmatic, tokens.maxi);
        try tokens.want.token0() returns (address _token0) {
            address _token1 = tokens.want.token1();
            tokens.token0 = IERC20(_token0);
            tokens.token1 = IERC20(_token1);
            makeEarnedToXPath(paths.earnedToToken0, paths.earnedToWmatic, tokens.token0);
            makeEarnedToXPath(paths.earnedToToken1, paths.earnedToWmatic, tokens.token1);
        } catch {
            require(!isLPStrategy, "failed to retrieve token0/1 data");
        }

    }
    
    function makeEarnedToWmaticPath(Tokens storage tokens, Paths storage paths, address middleStep) internal {
        
        address[] storage path = paths.earnedToWmatic;
        require(path.length == 0, "already initialized");
        address earnedAddress = address(tokens.earned);
        address wmaticAddress = address(WMATIC);

         path.push(earnedAddress);
        if (tokens.earned == WMATIC) return;
        
        if (middleStep == address(0)) {
            path.push(wmaticAddress);
        } else {
            path.push(middleStep);
            path.push(wmaticAddress);
        }
    }
    function makeEarnedToXPath(address[] storage _path, address[] memory earnedToWmaticPath, IERC20 xToken) internal {
        
        address xAddress = address(xToken);
        
        if (earnedToWmaticPath[0] == xAddress) {
        } else if (earnedToWmaticPath[1] == xAddress) {
            _path.push(earnedToWmaticPath[0]);
        } else {
            for (uint i; i < earnedToWmaticPath.length; i++) {
                _path.push(earnedToWmaticPath[i]);
            }
        }
        _path.push(xAddress);
    }
    
}