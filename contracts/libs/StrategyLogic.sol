// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./IStrategyFish.sol";
import "./IUniPair.sol";
import "./IUniRouter02.sol";
import "./IVaultHealer.sol";
import "./IMasterchef.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

enum StratType { BASIC, MASTER_HEALER, MAXIMIZER, MAXIMIZER_CORE }

library StrategyLogic {
    using Math for uint256;
    using SafeERC20 for IERC20;
    
    struct Addresses {
        address vaultChef;
        address want;
        address earned;
        address masterChef;
        address maxiWant; // zero and unused except for maximizer vaults. This is the maximized want token
    }
    struct Settings {
        address uniRouterAddress;
        uint16 controllerFee;
        uint16 rewardRate;
        uint16 buyBackRate;
        uint16 withdrawFeeFactor;
        uint16 tolerance;
        address govAddress;
    }
    struct Paths {
        address[] earnedToWmatic;
        address[] earnedToUsdc;
        address[] earnedToFish;
        address[] earnedToToken0;
        address[] earnedToToken1;
        address[] token0ToEarned;
        address[] token1ToEarned;
        address[] earnedToMaxi;
    }
    struct Data {
        bytes32 uid;
        Addresses addresses;
        Settings settings;
        Paths paths;
        uint256 sharesTotal;
        uint256 burnedAmount;
        uint64 lastEarnBlock;
        uint24 pid;
        StratType stratType;
    }

    address public constant wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant fishAddress = 0x76bF0C28e604CC3fE9967c83b3C3F31c213cfE64;
    
    address public constant rewardAddress = 0x917FB15E8aAA12264DCBdC15AFef7cD3cE76BA39;
    address public constant withdrawFeeAddress = 0x5386881b46C37CdD30A748f7771CF95D7B213637;
    address public constant feeAddress = 0x5386881b46C37CdD30A748f7771CF95D7B213637;
    address public constant buyBackAddress = 0x000000000000000000000000000000000000dEaD;
    
    uint256 public constant feeMaxTotal = 1000;
    uint256 public constant feeMax = 10000; // 100 = 1%
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9900;
    
    event SetSettings(
        address _uniRouterAddress,
        uint16 _controllerFee,
        uint16 _rewardRate,
        uint16 _buyBackRate,
        uint16 _withdrawFeeFactor,
        uint16 _tolerance
    );
    
    function makeMaxiCore(
        Data storage data,
        address _vaultHealer,
        address _masterchefAddress,
        address _uniRouterAddress,
        uint256 _pid,
        address _wantAddress, //want == earned for maximizer core
        uint256 _tolerance,
        address _earnedToWmaticStep //address(0) if swapping earned->wmatic directly, or the address of an intermediate trade token such as weth
    ) public {
        Addresses storage addresses = data.addresses;
        Settings storage settings = data.settings;
        
        addresses.vaultChef = _vaultHealer;
        addresses.want =  _wantAddress;
        addresses.earned = _wantAddress;
        addresses.masterChef = _masterchefAddress;
        addresses.maxiWant = _wantAddress;
        
    }
    
    function setSettings_(
        Data storage data,
        uint16 _controllerFee,
        uint16 _rewardRate,
        uint16 _buyBackRate,
        uint16 _withdrawFeeFactor,
        uint16 _tolerance,
        address _uniRouterAddress
    ) public {
        require(_controllerFee + _rewardRate + _buyBackRate <= feeMaxTotal, "Max fee of 10%");
        require(_withdrawFeeFactor >= withdrawFeeFactorLL, "_withdrawFeeFactor too low");
        require(_withdrawFeeFactor <= withdrawFeeFactorMax, "_withdrawFeeFactor too high");
        Settings storage settings = data.settings;
        settings.controllerFee = _controllerFee;
        settings.rewardRate = _rewardRate;
        settings.buyBackRate = _buyBackRate;
        settings.withdrawFeeFactor = _withdrawFeeFactor;
        settings.tolerance = _tolerance;
        settings.uniRouterAddress = _uniRouterAddress;

        emit SetSettings(
            _uniRouterAddress,
            _controllerFee,
            _rewardRate,
            _buyBackRate,
            _withdrawFeeFactor,
            _tolerance
        );
    }

    function _safeSwap(
        Settings storage settings,
        uint256 _amountIn,
        address[] storage _path,
        address _to
    ) public returns (uint burnedAmount) {
        uint256[] memory amounts = IUniRouter02(settings.uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length - 1];
        
        if (_path[_path.length - 1] == fishAddress && _to == buyBackAddress) {
            burnedAmount = amountOut;
        }

        IUniRouter02(settings.uniRouterAddress).swapExactTokensForTokens(
            _amountIn,
            amountOut,
            _path,
            _to,
            block.timestamp
        );
    }

    function _safeSwapWmatic(
        Settings storage settings,
        uint256 _amountIn,
        address[] storage _path,
        address _to
    )  public {
        uint256[] memory amounts = IUniRouter02(settings.uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length - 1];

        IUniRouter02(settings.uniRouterAddress).swapExactTokensForETH(
            _amountIn,
            amountOut,
            _path,
            _to,
            block.timestamp
        );
    }

    function payAllFees(
        Data storage data,
        uint _earnedAmt
    ) public returns (uint earnedAfterFees) {
        
        Settings storage settings = data.settings;
        Paths storage paths = data.paths;
        
        earnedAfterFees = _earnedAmt;
        
        //distributeFees
        if (settings.controllerFee > 0) {
            uint256 fee = _earnedAmt * settings.controllerFee / feeMax;
    
            _safeSwapWmatic(
                settings,
                fee,
                paths.earnedToWmatic,
                feeAddress
            );
            
            earnedAfterFees -= fee;
        }
    
        //distributeRewards
        if (settings.rewardRate > 0) {
            uint256 fee = _earnedAmt * settings.rewardRate / feeMax;
    
            uint256 usdcBefore = IERC20(usdcAddress).balanceOf(address(this));
            
            _safeSwap(
                settings,
                fee,
                paths.earnedToUsdc,
                address(this)
            );
            
            uint256 usdcAfter = IERC20(usdcAddress).balanceOf(address(this)) - usdcBefore;
            
            IStrategyFish(rewardAddress).depositReward(usdcAfter);
            
            earnedAfterFees -= fee;
        }
    
        //buyBack
        if (settings.buyBackRate > 0) {
            uint256 buyBackAmt = _earnedAmt * settings.buyBackRate / feeMax;
    
            data.burnedAmount += _safeSwap(
                settings,
                buyBackAmt,
                paths.earnedToFish,
                buyBackAddress
            );

            earnedAfterFees -= buyBackAmt;
        }
    }
    
    //BaseStrategyLP
    function convertDustToEarned_(Data storage data) public {
        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().
        
        require(data.stratType == StratType.MASTER_HEALER, "must be LP strategy");
        
        Paths storage paths = data.paths;
        Settings storage settings = data.settings;
        
        address token0Address = paths.token0ToEarned[0];
        address token1Address = paths.token1ToEarned[0];
        address earnedAddress = paths.token0ToEarned[paths.token0ToEarned.length - 1];

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Amt > 0 && token0Address != earnedAddress) {
            // Swap all dust tokens to earned tokens
            _safeSwap(
                settings,
                token0Amt,
                paths.token0ToEarned,
                address(this)
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Amt > 0 && token1Address != earnedAddress) {
            // Swap all dust tokens to earned tokens
            _safeSwap(
                settings,
                token1Amt,
                paths.token1ToEarned,
                address(this)
            );
        }
    }
    
    function earn_(Data storage data) public {
        
        Addresses storage addresses = data.addresses;
        Paths storage paths = data.paths;
        Settings storage settings = data.settings;
        
        // anti-rug: don't charge fees on unearned tokens
        uint256 unearnedAmt = IERC20(addresses.earned).balanceOf(address(this));
        
        // Harvest farm tokens
        _vaultHarvest(data);
        
        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(addresses.earned).balanceOf(address(this)) - unearnedAmt;
        
        if (earnedAmt > 0) payAllFees(data, earnedAmt);
        
        earnedAmt = IERC20(addresses.earned).balanceOf(address(this));
        
        if (data.stratType == StratType.MASTER_HEALER) {
    
            address token0Address = paths.token0ToEarned[0];
            address token1Address = paths.token1ToEarned[0];
        
            if (addresses.earned != token0Address) {
                // Swap half earned to token0
                _safeSwap(
                    data.settings,
                    earnedAmt / 2,
                    paths.earnedToToken0,
                    address(this)
                );
            }
    
            if (addresses.earned != token1Address) {
                // Swap half earned to token1
                _safeSwap(
                    settings,
                    earnedAmt / 2,
                    paths.earnedToToken1,
                    address(this)
                );
            }
    
            // Get want tokens, ie. add liquidity
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            if (token0Amt > 0 && token1Amt > 0) {
                IUniRouter02(settings.uniRouterAddress).addLiquidity(
                    token0Address,
                    token1Address,
                    token0Amt,
                    token1Amt,
                    0,
                    0,
                    address(this),
                    block.timestamp
                );
            }
    
        } else if (data.stratType == StratType.MAXIMIZER) {
            
            if (addresses.earned != addresses.maxiWant) {
                // Swap all earned to maximized token
                _safeSwap(
                    settings,
                    earnedAmt,
                    paths.earnedToMaxi,
                    address(this)
                );
            }
    
            IVaultHealer(addresses.vaultChef).maximizerDeposit(IERC20(addresses.maxiWant).balanceOf(address(this)));
            
        } else if (data.stratType == StratType.MAXIMIZER_CORE) {
        } else {
            revert("earn_ function broken");
        }
        
        data.lastEarnBlock = uint64(block.number);
        _farm(data);
    }
    
    function resetAllowances(Data storage data) public {

        Settings storage settings = data.settings;
        Addresses storage addresses = data.addresses;
        Paths storage paths = data.paths;

        if (data.stratType == StratType.MASTER_HEALER) {
            address token0Address = paths.token0ToEarned[0];
            address token1Address = paths.token1ToEarned[0];
    
            IERC20(token0Address).safeApprove(settings.uniRouterAddress, type(uint256).max);
            IERC20(token1Address).safeApprove(settings.uniRouterAddress, type(uint256).max);
            
        } else if (data.stratType == StratType.MAXIMIZER_CORE) {
            IERC20(addresses.want).safeApprove(settings.uniRouterAddress, type(uint256).max);
        } else if (data.stratType == StratType.MAXIMIZER) {
            IERC20(addresses.want).safeApprove(addresses.vaultChef, type(uint256).max);
        } else {
            revert("resetAllowances function broken");
        }
        
        IERC20(addresses.want).safeApprove(addresses.masterChef, type(uint256).max);
        IERC20(addresses.earned).safeApprove(settings.uniRouterAddress, type(uint256).max);
        IERC20(usdcAddress).safeApprove(rewardAddress, type(uint256).max);
    }
    
    function deposit_(Data storage data, uint256 _wantAmt) public returns (uint256) {
        
        Addresses storage addresses = data.addresses;
        
        // Call must happen before transfer
        uint256 wantLockedBefore = wantLockedTotal(data);

        IERC20(addresses.want).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );

        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        uint256 sharesAdded = _farm(data);
        if (data.sharesTotal > 0) {
            sharesAdded = sharesAdded * data.sharesTotal / wantLockedBefore;
        }
        data.sharesTotal += sharesAdded;

        return sharesAdded;
    }

    function withdraw_(Data storage data, uint256 _wantAmt) public returns (uint256) {
        require(_wantAmt > 0, "_wantAmt is 0");
        
        Addresses storage addresses = data.addresses;
        Settings storage settings = data.settings;
        
        uint256 wantAmt = IERC20(addresses.want).balanceOf(address(this));
        
        // Check if strategy has tokens from panic
        if (_wantAmt > wantAmt) {
            _vaultWithdraw(data, _wantAmt - wantAmt);
            wantAmt = IERC20(addresses.want).balanceOf(address(this));
        }

        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        uint _wantLockedTotal = wantLockedTotal(data);

        if (_wantAmt > _wantLockedTotal) {
            _wantAmt = _wantLockedTotal;
        }

        uint256 sharesRemoved = (_wantAmt * data.sharesTotal).ceilDiv(_wantLockedTotal);
        if (sharesRemoved > data.sharesTotal) {
            sharesRemoved = data.sharesTotal;
        }
        data.sharesTotal -= sharesRemoved;
        
        // Withdraw fee
        uint256 withdrawFee = _wantAmt * (withdrawFeeFactorMax - settings.withdrawFeeFactor) / withdrawFeeFactorMax;
        if (withdrawFee > 0) {
            IERC20(addresses.want).safeTransfer(withdrawFeeAddress, withdrawFee);
        }
        
        _wantAmt -= withdrawFee;

        IERC20(addresses.want).safeTransfer(addresses.vaultChef, _wantAmt);

        return sharesRemoved;
    }
    
    function _farm(Data storage data) internal returns (uint256) {
        
        Addresses storage addresses = data.addresses;
        
        uint256 wantAmt = IERC20(addresses.want).balanceOf(address(this));
        if (wantAmt == 0) return 0;
        
        uint256 sharesBefore = vaultSharesTotal(data);
        _vaultDeposit(data, wantAmt);
        uint256 sharesAfter = vaultSharesTotal(data);
        
        return sharesAfter - sharesBefore;
    }
    
    function _vaultDeposit(Data storage data, uint256 _amount) internal {
        Addresses storage addresses = data.addresses;
        IMasterchef(addresses.masterChef).deposit(data.pid, _amount);
    }
    
    function _vaultWithdraw(Data storage data, uint256 _amount) internal {
        Addresses storage addresses = data.addresses;
        IMasterchef(addresses.masterChef).withdraw(data.pid, _amount);
    }
    
    function _vaultHarvest(Data storage data) internal {
        Addresses storage addresses = data.addresses;
        IMasterchef(addresses.masterChef).withdraw(data.pid, 0);
    }
    
    function vaultSharesTotal(Data storage data) public view returns (uint256) {
        Addresses storage addresses = data.addresses;
        (uint256 amount,) = IMasterchef(addresses.masterChef).userInfo(data.pid, address(this));
        return amount;
    }
    
    function wantLockedTotal(Data storage data) public view returns (uint256) {
        Addresses storage addresses = data.addresses;
        return IERC20(addresses.want).balanceOf(address(this)) + vaultSharesTotal(data);
    }
    
    function _emergencyVaultWithdraw(Data storage data) internal {
        Addresses storage addresses = data.addresses;
        IMasterchef(addresses.masterChef).emergencyWithdraw(data.pid);
    }
    /*
    event Paused(address account, bytes32 uid);
    event Unpaused(address account, bytes32 uid);
    
    function paused(Data storage data) public view returns (bool) {
        return data._paused;
    }

    modifier whenNotPaused(Data storage data) {
        require(!paused(data), "Pausable: paused");
        _;
    }
    
    modifier whenPaused(Data storage data) {
        require(paused(data), "Pausable: not paused");
        _;
    }
    function _pause(Data storage data) internal whenNotPaused(data) {
        data._paused = true;
        emit Paused(msg.sender, data.uid);
    }
    function _unpause(Data storage data) internal whenPaused(data) {
        data._paused = false;
        emit Unpaused(msg.sender, data.uid);
    }
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner, bytes32 uid);
    
    modifier onlyOwner(Data storage data) {
        require(owner(data) == msg.sender, "Ownable: caller is not the owner");
        _;
    }
    
    function renounceOwnership(Data storage data) public virtual onlyOwner(data) {
        _setOwner(address(0));
    }
    
    function transferOwnership(Data storage data, address newOwner) public onlyOwner(data) {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(data, newOwner);
    }

    function _setOwner(Data storage data, address newOwner) private {
        address oldOwner = data._owner;
        data._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner, data.uid);
    }
    
    function setGov(Data storage data, address _govAddress) public onlyGov(data) {
        data.settings.govAddress = _govAddress;
    }
    
    modifier onlyGov(Data storage data) {
        require(msg.sender == data.settings.govAddress, "!gov");
        _;
    }
    */
    
}