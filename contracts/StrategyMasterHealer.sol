// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";
import "./BaseStrategyLPSingle.sol";

contract StrategyMasterHealer is BaseStrategyLPSingle {

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
        super._initialize();
        
        pid = _pid;
        tolerance = _tolerance;
        
        addresses = StrategyData.Addresses({
            gov: _govAddress,
            want: _wantAddress,
            earned: _earnedAddress,
            router: _uniRouter,
            vaultChef: msg.sender,
            masterChef: _masterChef,
            token0: address(0),
            token1: address(0),
            maxi: address(0)
        });

        StrategyData.buildAllPaths(addresses, paths, _earnedToWmaticStep, true);

        transferOwnership(msg.sender);
        _resetAllowances();
        stratType = StratType.MASTER_HEALER;
    }

    function _vaultDeposit(uint256 _amount) internal override {
        IMasterchef(addresses.masterChef).deposit(pid, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMasterchef(addresses.masterChef).withdraw(pid, _amount);
    }
    
    function vaultSharesTotal() public override view returns (uint256) {
        (uint256 amount,) = IMasterchef(addresses.masterChef).userInfo(pid, address(this));
        return amount;
    }

    function _resetAllowances() internal override {
        IERC20(addresses.want).approve(addresses.masterChef, type(uint256).max);
        IERC20(addresses.earned).approve(addresses.router, type(uint256).max);
        IERC20(usdcAddress).approve(rewardAddress, type(uint256).max);
    }
    
    function _emergencyVaultWithdraw() internal override {
        IMasterchef(addresses.masterChef).emergencyWithdraw(pid);
    }
}