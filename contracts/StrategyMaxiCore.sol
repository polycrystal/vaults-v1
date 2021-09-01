// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";
import "./libs/StrategySwapPaths.sol";
import "./BaseStrategy.sol";

contract StrategyMaxiCore is BaseStrategy {
    using SafeERC20 for IERC20;

    address public immutable masterchefAddress;
    uint256 public immutable pid;
    
    constructor(
        address _govAddress,
        address _vaultHealer,
        address _masterchefAddress,
        address _uniRouterAddress,
        uint256 _pid,
        address _wantAddress, //want == earned for maximizer core
        uint256 _tolerance,
        address _earnedToWmaticStep //address(0) if swapping earned->wmatic directly, or the address of an intermediate trade token such as weth
    ) BaseStrategy(_vaultHealer, _wantAddress, _wantAddress, _wantAddress, StratType.MAXIMIZER_CORE) {
        govAddress = _govAddress;
        masterchefAddress = _masterchefAddress;
        uniRouterAddress = _uniRouterAddress;

        pid = _pid;
        tolerance = _tolerance;
        
        earnedToWmaticPath = StrategySwapPaths.makeEarnedToWmaticPath(_wantAddress, _earnedToWmaticStep);
        earnedToUsdcPath = StrategySwapPaths.makeEarnedToXPath(earnedToWmaticPath, usdcAddress);
        earnedToFishPath = StrategySwapPaths.makeEarnedToXPath(earnedToWmaticPath, fishAddress);

        transferOwnership(_vaultHealer);
        
        _resetAllowances(_wantAddress, _masterchefAddress, _vaultHealer);
    }

    function _resetAllowances(address _want, address _masterChef, address _vaultChef) internal {

        
        IERC20(_want).safeApprove(_masterChef, uint256(0));
        IERC20(_want).safeIncreaseAllowance(
            _masterChef,
            type(uint256).max
        );

        IERC20(_want).safeApprove(uniRouterAddress, uint256(0));
        IERC20(_want).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

        IERC20(usdcAddress).safeApprove(rewardAddress, uint256(0));
        IERC20(usdcAddress).safeIncreaseAllowance(
            rewardAddress,
            type(uint256).max
        );
        
        IERC20(_want).safeApprove(_vaultChef, uint256(0));
        IERC20(_want).safeIncreaseAllowance(
            _vaultChef,
            type(uint256).max
        );
    }
    
    
}