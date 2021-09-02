// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";

import "./BaseStrategyLPSingle.sol";

contract StrategyMasterHealer is BaseStrategyLPSingle {
    using SafeERC20 for IERC20;

    function initialize(
        uint256 _pid,
        uint256 _tolerance,
        address _govAddress,
        address _masterChef,
        address _uniRouter,
        address _wantAddress,
        address _earnedAddress,
        address _earnedToWmaticStep
    ) external {
        _baseInit();
        
        govAddress = _govAddress;
        vaultChefAddress = msg.sender;
        masterchefAddress = _masterChef;
        uniRouterAddress = _uniRouter;
        wantAddress = _wantAddress;
        earnedAddress = _earnedAddress;

        pid = _pid;
        tolerance = _tolerance;

        StrategySwapPaths.buildAllPaths(paths, _earnedAddress, _earnedToWmaticStep, crystlAddress, _wantAddress, address(0));

        transferOwnership(msg.sender);
        
        _resetAllowances();
        stratType = StratType.MASTER_HEALER;
    }

    function _vaultDeposit(uint256 _amount) internal override {
        IMasterchef(masterchefAddress).deposit(pid, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMasterchef(masterchefAddress).withdraw(pid, _amount);
    }
    
    function _vaultHarvest() internal override {
        IMasterchef(masterchefAddress).withdraw(pid, 0);
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = IMasterchef(masterchefAddress).userInfo(pid, address(this));
        return amount;
    }
    
    function wantLockedTotal() public override view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this)) + vaultSharesTotal();
    }

    function _resetAllowances() internal override {
        IERC20(wantAddress).safeApprove(masterchefAddress, type(uint256).max);
        IERC20(earnedAddress).safeApprove(uniRouterAddress, type(uint256).max);
        IERC20(paths.token0ToEarned[0]).safeApprove(uniRouterAddress, type(uint256).max);
        IERC20(paths.token1ToEarned[0]).safeApprove(uniRouterAddress, type(uint256).max);
        IERC20(usdcAddress).safeApprove(rewardAddress, type(uint256).max);
    }
    
    function _emergencyVaultWithdraw() internal override {
        IMasterchef(masterchefAddress).emergencyWithdraw(pid);
    }
}