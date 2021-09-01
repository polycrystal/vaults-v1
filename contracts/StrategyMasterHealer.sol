// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";
import "./libs/Pyrite.sol";
import "./BaseStrategyLPSingle.sol";

contract StrategyMasterHealer is BaseStrategy {
    using SafeERC20 for IERC20;
    
    struct InitAddresses {
        address vaultChef;
        address masterChef;
        address uniRouter;
        address want;
        address earned;
    }

    constructor(
        uint24 _pid,
        uint16 _tolerance,
        InitAddresses memory _initAddr,
        address[] memory _earnedToWmaticPath,
        address[] memory _earnedToUsdcPath,
        address[] memory _earnedToFishPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path
    ) BaseStrategy(_initAddr.vaultChef, _initAddr.want, _initAddr.earned, address(0), StratType.MASTER_HEALER) {
        
        BaseStrategyLogic.Settings storage settings = data.settings;
        BaseStrategyLogic.Addresses storage addresses = data.addresses;
        BaseStrategyLogic.Paths storage paths = data.paths;
        
        settings.govAddress = msg.sender;
        
        addresses.masterChef = _initAddr.masterChef;
        settings.uniRouterAddress = _initAddr.uniRouter;

        data.pid = _pid;
        settings.tolerance = _tolerance;

        paths.earnedToWmatic = _earnedToWmaticPath;
        paths.earnedToUsdc = _earnedToUsdcPath;
        paths.earnedToFish = _earnedToFishPath;
        paths.earnedToToken0 = _earnedToToken0Path;
        paths.earnedToToken1 = _earnedToToken1Path;
        paths.token0ToEarned = Pyrite.reverseArray(_earnedToToken0Path);
        paths.token1ToEarned = Pyrite.reverseArray(_earnedToToken1Path);

        transferOwnership(_initAddr.vaultChef);
        
        BaseStrategyLogic.resetAllowances(data);
    }

}