// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";
import "./libs/IVaultHealer.sol";
import "./libs/StrategySwapPaths.sol";
import "./BaseStrategy.sol";

//Can be used for both single-stake and LP want tokens
contract StrategyMaxiMasterHealer is BaseStrategy {
    using SafeERC20 for IERC20;

    address public immutable masterchefAddress;
    uint256 public immutable pid;

    constructor(
        address _govAddress,
        address _vaultHealer,
        address _masterChef,
        address _uniRouter,
        address _want,
        address _earned,
        address _maxi,
        uint256 _pid,
        uint256 _tolerance,
        address _earnedToWmaticStep //address(0) if swapping earned->wmatic directly, or the address of an intermediate trade token such as weth
    ) BaseStrategy(_vaultHealer, _want, _earned, _maxi, StratType.MAXIMIZER) {
        
        BaseStrategyLogic.Addresses storage addresses = data.addresses;
        BaseStrategyLogic.Settings storage settings = data.settings;
        BaseStrategyLogic.Paths storage paths = data.paths;
        
        data.settings.govAddress = _govAddress;

        addresses.masterChef = _masterChef;
        data.settings.uniRouterAddress = _uniRouter;
        
        data.pid = _pid;
        data.tolerance = _tolerance;
        
        paths.earnedToWmatic = StrategySwapPaths.makeEarnedToWmaticPath(_earned, _earnedToWmaticStep);
        paths.earnedToUsdc = StrategySwapPaths.makeEarnedToXPath(paths.earnedToWmatic, BaseStrategyLogic.usdcAddress);
        paths.earnedToFish = StrategySwapPaths.makeEarnedToXPath(paths.earnedToWmatic, BaseStrategyLogic.fishAddress);
        paths.earnedToMaxi = StrategySwapPaths.makeEarnedToXPath(paths.earnedToWmatic, _maxi);

        transferOwnership(_vaultHealer);
        
        _resetAllowances(_want, _earned, _masterChef);
    }
}