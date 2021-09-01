// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./libs/IStrategyFish.sol";
import "./libs/IUniPair.sol";
import "./libs/StrategyLogic.sol";
abstract contract BaseStrategy is Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    StrategyLogic.Data public data;
    
    constructor(address _vaultChef, address _want, address _earned, address _maxi, StratType _stratType) {
        data.addresses.vaultChef = _vaultChef;
        data.addresses.want = _want;
        data.addresses.earned = _earned;
        data.addresses.maxiWant = _maxi;
        data.stratType = _stratType;
        
        data.settings.controllerFee = 50;
        data.settings.buyBackRate = 450;
        data.settings.withdrawFeeFactor = 9990; // 0.1% withdraw fee
        
        data.lastEarnBlock = uint64(block.number);
        data._owner = msg.sender;
    }

    function convertDustToEarned() external nonReentrant {
        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().
        StrategyLogic.convertDustToEarned_(data);
    }

    function earn() external nonReentrant onlyOwner {
        StrategyLogic.earn_(data);
    }

    function vaultSharesTotal() external view returns (uint256) {
        return StrategyLogic.vaultSharesTotal(data);
    }
    
    function wantLockedTotal() external view returns (uint256) {
        return StrategyLogic.wantLockedTotal(data);
    }
    
    function deposit(address /*_userAddress*/, uint256 _wantAmt) external onlyOwner nonReentrant whenNotPaused returns (uint256) {
        return StrategyLogic.deposit_(data, _wantAmt);
    }

    function withdraw(address /*_userAddress*/, uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256) {
        return StrategyLogic.withdraw_(data, _wantAmt);
    }

    function resetAllowances() external onlyGov {
        StrategyLogic.resetAllowances(data);
    }

    function pause() external onlyGov {
        _pause();
    }

    function unpause() external onlyGov {
        _unpause();
        StrategyLogic.resetAllowances(data);
    }

    function panic() external onlyGov {
        _pause();
        StrategyLogic._emergencyVaultWithdraw(data);
    }

    function unpanic() external onlyGov {
        _unpause();
        StrategyLogic._farm(data);
    }

    
    function setSettings(
        uint16 _controllerFee,
        uint16 _rewardRate,
        uint16 _buyBackRate,
        uint16 _withdrawFeeFactor,
        uint16 _tolerance,
        address _uniRouterAddress
    ) external onlyGov {
        StrategyLogic.setSettings_(data.settings, _controllerFee, _rewardRate, _buyBackRate, _withdrawFeeFactor, _tolerance, _uniRouterAddress);
    }
}