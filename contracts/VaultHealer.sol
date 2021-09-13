// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./libs/IStrategy.sol";

contract VaultHealer is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using VaultData for Vault;
    using VaultData for Vault[];
    using VaultData for MCore;

    MCore public mCore;
    Vault[] public vaults;
    mapping(address => bool) private strats;
    MaximizerSettings public maxiSettings = MaximizerSettings({
        min: 10,
        _default: 50,
        max: 100
    });

    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetMaximizer(uint64 min, uint64 _default, uint64 max);
    
    function poolLength() external view returns (uint256) {
        return vaults.length;
    }
    
    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner nonReentrant needsCore {
        require(!strats[_strat], "Existing strategy");
        Vault storage pool = vaults.push();
        
        pool.strat = IStrategy(_strat);
        pool.want = IERC20(pool.strat.wantAddress());
        strats[_strat] = true;
        resetSingleAllowance(vaults.length - 1);
        emit AddPool(_strat);
    }
    
    //The maximizer core strategy is required for the vault to function correctly
    function addCore(address _strat) external onlyOwner nonReentrant {
        require(address(mCore.strat) == address(0), "Only one maximizer core allowed");
        
        mCore.strat = IStrategyCore(_strat);
        mCore.want = IERC20(mCore._strat.wantAddress());
        strats[_strat] = true;
        resetSingleAllowance(type(uint).max);
    }
    
    modifier needsCore() {
        require(address(mCore.strat) != address(0), "Maximizer core not installed");
    }

    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint cTokens, uint mTokens) {
        if (_pid == type(uint).max) return stakedCoreTokens();
        return vaults[_pid].balance(_user);
    }

////NEW
    function stakedCoreTokens(address _user) internal view returns (uint256) {
        return mCore.balance(vaults, _user);
    }

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt) external nonReentrant needsCore {
        _deposit(_pid, _wantAmt, msg.sender);
    }

    // For depositing for other users
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant needsCore {
        _deposit(_pid, _wantAmt, _to);
    }
    
    function depositCore(uint256 _wantAmt, address _to) external nonReentrant needsCore {
        _depositCore(_wantAmt, _to);
    }
    
    function _depositCore(uint256 _wantAmt, address _to) internal {
        if (_wantAmt > 0) {
            // Call must happen before transfer
            uint256 wantBefore = mCore.strat.wantLockedTotal();
            mCore.want.safeTransferFrom(msg.sender, mCore.strat, _wantAmt);
            uint tokensAdded = mCore.strat.deposit(msg.sender, wantBefore, _wantAmt);
            
            mCore.deposit(_to, tokensAdded);
        }
        emit Deposit(_to, type(uint).max, _wantAmt);
        
    }
    

    function _deposit(uint256 _pid, uint256 _wantAmt, address _to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.strat != address(0), "That strategy does not exist");
        UserInfo storage user = userInfo[_pid][_to];

        if (_wantAmt > 0) {
            // Call must happen before transfer
            uint256 wantBefore = IERC20(pool.want).balanceOf(address(this));
            pool.want.safeTransferFrom(msg.sender, address(this), _wantAmt);
            uint256 finalDeposit = IERC20(pool.want).balanceOf(address(this)).sub(wantBefore);

            // Proper deposit amount for tokens with fees
            uint256 sharesAdded = IStrategy(poolInfo[_pid].strat).deposit(_to, finalDeposit);
            user.shares = user.shares.add(sharesAdded);
        }
        emit Deposit(_to, _pid, _wantAmt);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) external nonReentrant needsCore {
        _withdraw(_pid, _wantAmt, msg.sender);
    }

    // For withdrawing to other address
    function withdraw(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant needsCore {
        _withdraw(_pid, _wantAmt, _to);
    }

    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) internal {
        PoolInfo storage pool = poolInfo[_pid];
        require(pool.strat != address(0), "That strategy does not exist");
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw want tokens
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved = IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(_to, _wantAmt);
        }
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    // Withdraw everything from pool for yourself
    function withdrawAll(uint256 _pid) external {
        _withdraw(_pid, type(uint256).max, msg.sender);
    }

    function resetAllowances() external onlyOwner {
        for (uint256 i=0; i<poolInfo.length; i++) {
            PoolInfo storage pool = poolInfo[i];
            pool.want.safeApprove(pool.strat, uint256(0));
            pool.want.safeIncreaseAllowance(pool.strat, type(uint256).max);
        }
    }

    function earnAll() external {
        for (uint256 i=0; i<poolInfo.length; i++) {
            if (!IStrategy(poolInfo[i].strat).paused())
                IStrategy(poolInfo[i].strat).earn(_msgSender());
        }
    }

    function earnSome(uint256[] memory pids) external {
        for (uint256 i=0; i<pids.length; i++) {
            if (poolInfo.length >= pids[i] && !IStrategy(poolInfo[pids[i]].strat).paused())
                IStrategy(poolInfo[pids[i]].strat).earn(_msgSender());
        }
    }

    function resetSingleAllowance(uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        pool.want.safeApprove(pool.strat, uint256(0));
        pool.want.safeIncreaseAllowance(pool.strat, type(uint256).max);
    }
    function setMaximizerSettings(uint64 _min, uint64 __default, uint64 _max) external onlyOwner {
        require(_min <= 1e18 && __default <= 1e18 && _max <= 1e18, "can't exceed 1e18 == 100%");
        require(_min <= __default && __default <= _max, "min <= default <= max");
        maxiSettings = MaximizerSettings({
            min: 10,
            _default: 50,
            max: 100
        });
        emit SetMaximizer(_min, __default, _max);
    }
}