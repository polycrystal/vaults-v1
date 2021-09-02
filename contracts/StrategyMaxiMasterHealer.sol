// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";
import "./libs/IVaultHealer.sol";
import "./BaseStrategyMaxiSingle.sol";

//Can be used for both single-stake and LP want tokens
contract StrategyMaxiMasterHealer is BaseStrategyMaxiSingle {

    function initialize(
        uint256 _pid,
        uint256 _tolerance,
        address _govAddress,
        address _masterChef,
        address _uniRouter,
        address _wantAddress, 
        address _earnedAddress,
        address _earnedToWmaticStep //address(0) if swapping earned->wmatic directly, or the address of an intermediate trade token such as weth
    ) external {
        
        _baseInit();

        govAddress = _govAddress;

        vaultChefAddress = msg.sender;
        masterchefAddress = _masterChef;
        uniRouterAddress = _uniRouter;
        wantAddress = _wantAddress;
        earnedAddress = _earnedAddress;
        (maxiAddress,) = IVaultHealer(vaultChefAddress).poolInfo(0);
        
        pid = _pid;
        tolerance = _tolerance;
        
        StrategySwapPaths.buildAllPaths(paths, _wantAddress, _earnedToWmaticStep, crystlAddress, _wantAddress, maxiAddress);
        
        transferOwnership(vaultChefAddress);
        
        stratType = StratType.MAXIMIZER;
        _resetAllowances();
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
        IERC20(wantAddress).approve(masterchefAddress, type(uint256).max);
        IERC20(earnedAddress).approve(uniRouterAddress, type(uint256).max);
        IERC20(usdcAddress).approve(rewardAddress, type(uint256).max);
    }
    
    function _emergencyVaultWithdraw() internal override {
        IMasterchef(masterchefAddress).emergencyWithdraw(pid);
    }
}