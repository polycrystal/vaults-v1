// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./libs/IStrategyFish.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";

abstract contract BaseStrategy is Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 public panicTime; //time the vault was most recently panicked

    address public wantAddress;
    address public token0Address;
    address public token1Address;
    address public earnedAddress;
    
    address public uniRouterAddress;
    address public constant usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant fishAddress = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64; 
    address public constant rewardAddress = 0x917FB15E8aAA12264DCBdC15AFef7cD3cE76BA39; 
    address public constant withdrawFeeAddress = 0x5386881b46C37CdD30A748f7771CF95D7B213637; 
    address public constant feeAddress = 0x5386881b46C37CdD30A748f7771CF95D7B213637; 
    address public vaultChefAddress;
    address public govAddress;

    address public constant buyBackAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public controllerFee = 50;
    uint256 public rewardRate = 0;
    uint256 public buyBackRate = 450;
    uint256 public constant feeMaxTotal = 1000;
    uint256 public constant feeMax = 10000; // 100 = 1%

    uint256 public withdrawFeeFactor = 9990; // 0.1% withdraw fee
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9900; 

    uint256 public slippageFactor = 950; // 5% default slippage tolerance
    uint256 public constant slippageFactorUL = 995;
    uint256 public constant panicTimelock = 24 hours;
    
    // Frontend variables
    uint256 public tolerance;
    uint256 public burnedAmount;
    bool public active;

    address[] public earnedToWmaticPath;
    address[] public earnedToUsdcPath;
    address[] public earnedToFishPath;
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;
    
    event SetSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawFeeFactor,
        uint256 _slippageFactor,
        uint256 _tolerance,
        address _uniRouterAddress,
        bool _active
    );
    
    modifier onlyGov() {
        require(msg.sender == govAddress, "!gov");
        _;
    }

    function _vaultDeposit(uint256 _amount) internal virtual;
    function _vaultWithdraw(uint256 _amount) internal virtual;
    function _vaultHarvest() internal virtual;
    function earn() external virtual;
    function vaultSharesTotal() public virtual view returns (uint256);
    function wantLockedTotal() public virtual view returns (uint256);
    function _resetAllowances() internal virtual;
    function _emergencyVaultWithdraw() internal virtual;
    
    function deposit(uint256 _wantLockedTotal, uint256 _wantAmt) external onlyOwner nonReentrant whenNotPaused returns (uint256) {
        
        _farm(_wantAmt);
        return wantLockedTotal() - _wantLockedTotal;
    }

    function _farm(uint _wantAmt) internal {
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt < wantAmt) wantAmt = _wantAmt;
        if (wantAmt > 0) _vaultDeposit(wantAmt);
    }

    function withdraw(uint256 _wantLockedBefore, uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256 tokensRemoved, uint256 tokensToTransfer) {
        require(_wantAmt > 0, "_wantAmt is 0");
        
        tokensToTransfer = IERC20(wantAddress).balanceOf(address(this));
        
        if (_wantAmt > tokensToTransfer) {
            _vaultWithdraw(_wantAmt - tokensToTransfer);
            tokensToTransfer = IERC20(wantAddress).balanceOf(address(this));
        }
        tokensToTransfer = tokensToTransfer > _wantAmt ? _wantAmt : tokensToTransfer;
        uint wantLocked = wantLockedTotal();
        uint withdrawLoss = _wantLockedBefore > wantLocked ? _wantLockedBefore - wantLocked : 0;
        tokensRemoved = tokensToTransfer + withdrawLoss;
    }


    function earn(uint _mTokens, uint _minEarnAmount) external virtual nonReentrant whenNotPaused onlyOwner {
        // Harvest farm tokens
        _vaultHarvest();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        if (earnedAmt > minEarnAmount) {
            earnedAmt = distributeFees(earnedAmt);
            
            CrystalZap.zipToLP(addresses.earned, earnedAmt, addresses.token0, addresses.token1);
    
            lastEarnBlock = block.number;
    
            _farm();
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
        govAddress = _govAddress;
    }
    
    function setSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawFeeFactor,
        uint256 _slippageFactor,
        uint256 _tolerance,
        address _uniRouterAddress,
        bool _active
    ) external onlyGov {
        require(_controllerFee.add(_rewardRate).add(_buyBackRate) <= feeMaxTotal, "Max fee of 10%");
        require(_withdrawFeeFactor >= withdrawFeeFactorLL, "_withdrawFeeFactor too low");
        require(_withdrawFeeFactor <= withdrawFeeFactorMax, "_withdrawFeeFactor too high");
        require(_slippageFactor <= slippageFactorUL, "_slippageFactor too high");
        controllerFee = _controllerFee;
        rewardRate = _rewardRate;
        buyBackRate = _buyBackRate;
        withdrawFeeFactor = _withdrawFeeFactor;
        slippageFactor = _slippageFactor;
        tolerance = _tolerance;
        uniRouterAddress = _uniRouterAddress;
        active = _active;

        emit SetSettings(
            _controllerFee,
            _rewardRate,
            _buyBackRate,
            _withdrawFeeFactor,
            _slippageFactor,
            _tolerance,
            _uniRouterAddress,
            _active
        );
    }
    
    function _safeSwap(
        uint256 _amountIn,
        address[] memory _path,
        address _to
    ) internal {
        uint256[] memory amounts = IUniRouter02(uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];
        
        if (_path[_path.length.sub(1)] == fishAddress && _to == buyBackAddress) {
            burnedAmount = burnedAmount.add(amountOut);
        }

        IUniRouter02(uniRouterAddress).swapExactTokensForTokens(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            now.add(600)
        );
    }
    
    function _safeSwapWmatic(
        uint256 _amountIn,
        address[] memory _path,
        address _to
    ) internal {
        uint256[] memory amounts = IUniRouter02(uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        IUniRouter02(uniRouterAddress).swapExactTokensForETH(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            now.add(600)
        );
    }
}