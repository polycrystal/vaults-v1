// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";
import "./libs/StrategySwapPaths.sol";
import "./BaseStrategy.sol";

contract StrategyMaxiCore is BaseStrategy {
    using SafeERC20 for IERC20;

    address public masterchefAddress;
    uint256 public pid;
    
    constructor(
        address _govAddress,
        address _masterchefAddress,
        address _uniRouterAddress,
        uint256 _pid,
        address _wantAddress, //want == earned for maximizer core
        uint256 _tolerance,
        address _earnedToWmaticStep //address(0) if swapping earned->wmatic directly, or the address of an intermediate trade token such as weth
    ) {
        govAddress = _govAddress;
        vaultChefAddress = msg.sender;
        masterchefAddress = _masterchefAddress;
        uniRouterAddress = _uniRouterAddress;

        wantAddress = _wantAddress;

        pid = _pid;
        earnedAddress = _wantAddress;
        tolerance = _tolerance;
        
        earnedToWmaticPath = StrategySwapPaths.makeEarnedToWmaticPath(earnedAddress, _earnedToWmaticStep);
        earnedToUsdcPath = StrategySwapPaths.makeEarnedToXPath(earnedToWmaticPath, usdcAddress);
        earnedToFishPath = StrategySwapPaths.makeEarnedToXPath(earnedToWmaticPath, fishAddress);

        transferOwnership(vaultChefAddress);
        
        _resetAllowances();
        stratType = StratType.MAXIMIZER_CORE;
    }

    function earn() external override nonReentrant whenNotPaused onlyOwner {
        
        // anti-rug: don't charge fees on unearned tokens
        uint256 unearnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this)) - unearnedAmt;

        if (earnedAmt > 0) {
            earnedAmt = distributeFees(earnedAmt);
            earnedAmt = distributeRewards(earnedAmt);
            earnedAmt = buyBack(earnedAmt);
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }

    function _vaultDeposit(uint256 _amount) internal override {
        IMasterchef(masterchefAddress).deposit(pid, _amount);
    }
    
    function _vaultWithdraw(uint256 _amount) internal override {
        IMasterchef(masterchefAddress).withdraw(pid, _amount);
    }
    
    function _vaultHarvest() internal {
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
        
        IERC20(earnedAddress).safeApprove(vaultChefAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            vaultChefAddress,
            type(uint256).max
        );
    }
    
    function _emergencyVaultWithdraw() internal override {
        IMasterchef(masterchefAddress).emergencyWithdraw(pid);
    }
    
    
}