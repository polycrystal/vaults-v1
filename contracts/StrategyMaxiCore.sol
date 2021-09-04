// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./libs/IMasterchef.sol";
import "./BaseStrategy.sol";

contract StrategyMaxiCore is BaseStrategy {

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
            maxi: _wantAddress
        });
        
        StrategyData.buildAllPaths(addresses, paths, _earnedToWmaticStep, false);
        transferOwnership(msg.sender);
        _resetAllowances();
        stratType = StratType.MAXIMIZER_CORE;
    }

    function earn() external override nonReentrant whenNotPaused onlyOwner {
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(address.earned).balanceOf(address(this));

        if (earnedAmt > minEarnAmount && block.number > lastEarnBlock) {
            earnedAmt = distributeFees(earnedAmt);
    
            lastEarnBlock = block.number;
    
            _farm();
        }
    }

    function _vaultDeposit(uint256 _amount) internal override {
        IMasterchef(masterchefAddress).deposit(pid, _amount);
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
        IERC20(earnedAddress).approve(owner(), type(uint256).max);
    }
    
    function _emergencyVaultWithdraw() internal override {
        IMasterchef(masterchefAddress).emergencyWithdraw(pid);
    }
    
    
}