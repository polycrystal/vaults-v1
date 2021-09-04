// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./libs/IStrategyFish.sol";
import "./libs/CrystalZap.sol";
import "./libs/StrategyData.sol";
import "./libs/IStrategy.sol";

abstract contract BaseStrategy is Ownable, ReentrancyGuard, Pausable, Initializable {
    using Math for uint256;
    using SafeERC20 for IERC20;
    using CrystalZap for address[];
    
    bytes32 private __blankSlot; //used by proxies
    
    StratType public stratType;
    uint256 public pid;
    uint256 public lastEarnBlock;
    uint256 public controllerFee;
    uint256 public rewardRate;
    uint256 public buyBackRate;
    uint256 public withdrawFeeRate;
    uint256 public minEarnAmount; //minimum amount that earn() will bother to swap, below which gas and dust costs outweigh the benefits of compounding
    uint256 public panicTime; //time the vault was most recently panicked
    
    // Frontend variables
    uint256 public tolerance;
    uint256 public burnedAmount;
    
    StrategyData.Tokens internal tokens;
    StrategyData.Addresses internal addresses;
    StrategyData.Paths internal paths;
    StrategyData.Balances internal bal;
    
    function govAddress() external view returns (address) { return addresses.gov; }
    function wantAddress() external view returns (address) { return tokens.want; }
    function earnedAddress() external view returns (address) { return tokens.earned; }
    function uniRouterAddress() external view returns (address) { return addresses.router; }
    function vaultChefAddress() external view returns (address) { return owner(); }
    function masterchefAddress() external view returns (address) { return addresses.masterChef; }
    function token0Address() external view returns (address) { return tokens.token0; }
    function token1Address() external view returns (address) { return tokens.token1; }
    function maxiAddress() external view returns (address) { return tokens.maxi; }
    function cSharesTotal() external view returns (address) { return bal.cSharesTotal; }
    function mSharesTotal() external view returns (address) { return bal.mSharesTotal; }
    
    address public constant wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant crystlAddress = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    address public constant rewardAddress = 0x917FB15E8aAA12264DCBdC15AFef7cD3cE76BA39; 
    address public constant feeAddress = 0x5386881b46C37CdD30A748f7771CF95D7B213637; 
    address public constant buyBackAddress = 0x000000000000000000000000000000000000dEaD;
    
    uint256 public constant feeMaxTotal = 1000; //fees can't be more than 10% in total
    uint256 public constant BASIS_POINTS = 10000; // 100 = 1%
    uint256 public constant withdrawFeeLimit = 100; // max 1% withdrawal fee
    uint256 public constant panicTimelock = 24 hours;

    event SetSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawFeeFactor,
        uint256 _tolerance,
        address _uniRouterAddress,
        uint256 _minEarnAmount
    );
    
    modifier onlyGov() {
        require(msg.sender == addresses.gov, "!gov");
        _;
    }

    function _initialize() internal virtual initializer {
        lastEarnBlock = block.number;
        controllerFee = 50;
        buyBackRate = 450;
        withdrawFeeRate = 10; // 0.1% withdraw fee
        minEarnAmount = 1 gwei;
    }

    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual { _vaultWithdraw(0); }
    function earn() external virtual;
    function vaultSharesTotal() public virtual view returns (uint256);
    function vaultBalances() public view returns (uint256 wantBalance, uint256 vaultShares) {
        return (tokens.want.balanceOf(address(this)), vaultSharesTotal());
    }
    function wantLockedTotal() public view returns (uint256) {
        return tokens.want.balanceOf(address(this)) + vaultSharesTotal();
    }
    function _resetAllowances() internal virtual;
    function _emergencyVaultWithdraw() internal virtual;
    
    
    function deposit(uint256 _wantAmt, uint256 _cPercent, uint256 _wantBalanceBefore, uint256 _vaultSharesBefore) external onlyOwner nonReentrant whenNotPaused returns (uint256 tokensAdded) {

        // Proper deposit amount for tokens with fees, or vaults with deposit fees. With this method, if _vaultDeposit fails without reverting, the vault won't eat user tokens
         tokensAdded = tokens.want.balanceOf(address(this)) - _wantBalanceBefore;
        if (tokensAdded > 0) _vaultDeposit(tokensAdded);
        tokensAdded = wantLockedTotal() - _wantBalanceBefore - _vaultSharesBefore;
        
        return tokensAdded;
    }

    function withdraw(uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0, "_wantAmt is 0");
        
        uint256 wantAmt = IERC20(addresses.want).balanceOf(address(this));
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantAmt) {
            _vaultWithdraw(_wantAmt - wantAmt);
            wantAmt = IERC20(addresses.want).balanceOf(address(this));
        }

        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        if (_wantAmt > wantLockedTotal()) {
            _wantAmt = wantLockedTotal();
        }

        uint256 sharesRemoved = (_wantAmt * sharesTotal).ceilDiv(wantLockedTotal());
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal -= sharesRemoved;
        
        // Withdraw fee
        if (withdrawFeeRate > 0) {
            uint256 withdrawFee = (_wantAmt * withdrawFeeRate).ceilDiv(BASIS_POINTS);
            IERC20(addresses.want).safeTransfer(feeAddress, withdrawFee);
            _wantAmt -= withdrawFee;
        }

        IERC20(addresses.want).safeTransfer(owner(), _wantAmt);

        return sharesRemoved;
    }

    // To pay for earn function
    function distributeFees(uint256 _earnedAmt) internal returns (uint256 earnedAmt) {
        
        earnedAmt = _earnedAmt;
        
        if (controllerFee > 0) {
            uint256 fee = _earnedAmt * controllerFee / BASIS_POINTS;
            paths.earnedToWmatic.zip(fee, addresses.router, feeAddress);
            earnedAmt -= fee;
        }
        if (rewardRate > 0) {
            uint256 fee = _earnedAmt * rewardRate / BASIS_POINTS;
            uint256 usdcBefore = IERC20(usdcAddress).balanceOf(address(this));
            paths.earnedToUsdc.zip(fee, addresses.router, address(this));
            uint256 usdcAfter = IERC20(usdcAddress).balanceOf(address(this)) - usdcBefore;
            IStrategyFish(rewardAddress).depositReward(usdcAfter);
            earnedAmt -= fee;
        }
        if (buyBackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * buyBackRate / BASIS_POINTS;
            paths.earnedToCrystl.zip(buyBackAmt, addresses.router, buyBackAddress);
            burnedAmount += buyBackAmt;
            earnedAmt -= buyBackAmt;
        }
    }

    function resetAllowances() external onlyGov {
        _resetAllowances();
    }

    function pause() external onlyGov {
        _pause();
    }

    function unpause() public onlyGov {
        require(block.timestamp > panicTime + panicTimelock, "panic timelocked");
        _unpause();
        _resetAllowances();
        _farm();
    }

    function panic() external onlyGov {
        panicTime = block.timestamp;
        _pause();
        _emergencyVaultWithdraw();
    }

    function unpanic() external onlyGov {
        unpause();
    }

    function setGov(address _govAddress) external onlyGov {
        addresses.gov = _govAddress;
    }
    
    function setSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawFeeRate,
        uint256 _tolerance,
        address _uniRouterAddress,
        uint256 _minEarnAmount
    ) external onlyGov {
        require(_controllerFee + _rewardRate + _buyBackRate <= feeMaxTotal, "Max fee of 10%");
        require(_withdrawFeeRate <= withdrawFeeLimit, "_withdrawFeeFactor too high");
        require(_rewardRate == 0, "rewardRate not implemented yet");
        controllerFee = _controllerFee;
        rewardRate = _rewardRate;
        buyBackRate = _buyBackRate;
        withdrawFeeRate = _withdrawFeeRate;
        tolerance = _tolerance;
        addresses.router = _uniRouterAddress;
        minEarnAmount = _minEarnAmount;
        
        emit SetSettings(
            _controllerFee,
            _rewardRate,
            _buyBackRate,
            _withdrawFeeRate,
            _tolerance,
            _uniRouterAddress,
            _minEarnAmount
        );
    }
}