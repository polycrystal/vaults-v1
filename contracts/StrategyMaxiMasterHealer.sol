// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";

import "./BaseStrategyMaxiSingle.sol";

//Can be used for both single-stake and LP want tokens
contract StrategyMaxiMasterHealer is BaseStrategyMaxiSingle {
    using SafeERC20 for IERC20;

    address public masterchefAddress;
    uint256 public pid;

    struct InitAddresses {
        address vaultChef;
        address masterChef;
        address uniRouter;
        address want;
        address earned;
        address maxi;
    }

    constructor(
        uint256 _pid,
        uint256 _tolerance,
        InitAddresses memory _initAddr,
        address[] memory _earnedToWmaticPath,
        address[] memory _earnedToUsdcPath,
        address[] memory _earnedToFishPath,
        address[] memory _earnedToMaxiPath
    ) {
        govAddress = msg.sender;

        vaultChefAddress = _initAddr.vaultChef;
        masterchefAddress = _initAddr.masterChef;
        uniRouterAddress = _initAddr.uniRouter;
        wantAddress = _initAddr.want;
        earnedAddress = _initAddr.earned;
        maxiAddress = _initAddr.maxi;
        
        pid = _pid;
        tolerance = _tolerance;
        
        //We don't actually need the token0 and 1 addresses but we might as well try
        try IUniPair(wantAddress).token0() returns (address _token0) {
            token0Address = _token0;
            token1Address = IUniPair(wantAddress).token1();
        } catch {}
        
        earnedToWmaticPath = _earnedToWmaticPath;
        earnedToUsdcPath = _earnedToUsdcPath;
        earnedToFishPath = _earnedToFishPath;
        earnedToMaxiPath = _earnedToMaxiPath;

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
        IERC20(wantAddress).safeApprove(masterchefAddress, uint256(0));
        IERC20(wantAddress).safeIncreaseAllowance(
            masterchefAddress,
            type(uint256).max
        );

        IERC20(earnedAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            type(uint256).max
        );

        IERC20(usdcAddress).safeApprove(rewardAddress, uint256(0));
        IERC20(usdcAddress).safeIncreaseAllowance(
            rewardAddress,
            type(uint256).max
        );
    }
    
    function _emergencyVaultWithdraw() internal override {
        IMasterchef(masterchefAddress).emergencyWithdraw(pid);
    }
}