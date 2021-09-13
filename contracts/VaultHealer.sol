// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./libs/IStrategy.sol";
import "./Operators.sol";
import "./libs/VaultData.sol";

contract VaultHealer is Ownable, ReentrancyGuard, Operators {
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
    

    // Compounding Variables
    // 0: compound by anyone; 1: EOA only; 2: restricted to operators
    uint public compoundMode = 1;
    bool public autocompoundOn = true;

    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetCompoundMode(uint locked, bool automatic);
    event CompoundError(uint pid, bytes reason);
    event SetMaximizer(uint64 min, uint64 _default, uint64 max);

    function poolLength() external view returns (uint256) {
        return vaults.length;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner nonReentrant {
        require(!strats[_strat], "Existing strategy");
        Vault storage pool = vaults.push();
        
        pool.strat = IStrategy(_strat);
        pool.want = IERC20(pool.strat.wantAddress());
        strats[_strat] = true;
        resetSingleAllowance(vaults.length - 1);
        emit AddPool(_strat);
    }

    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint cTokens, uint mTokens) {
        return vaults[_pid].balance(_user);
    }

    function stakedCoreTokens(address _user) external view returns (uint256) {
        return mCore.balance(vaults, _user);
    }

    function deposit(uint256 _pid, uint256 _wantAmt) external nonReentrant autoCompound {
        _deposit(_pid, _wantAmt, msg.sender);
    }

    // For unique contract calls
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant onlyOperator {
        _deposit(_pid, _wantAmt, _to);
    }
    
    function _deposit(uint256 _pid, uint256 _wantAmt, address _to) internal {
        Vault storage pool = vaults[_pid];
        UserBalance storage user = pool.users[_to];

        if (_wantAmt > 0) {
            pool.want.safeTransferFrom(msg.sender, address(this), _wantAmt);

            uint256 sharesAdded = pool.strat.deposit(_to, _wantAmt);
            user.shares += sharesAdded;
        }
        emit Deposit(_to, _pid, _wantAmt);
    }

    function withdraw(uint256 _pid, uint256 _wantAmt) external nonReentrant autoCompound {
        _withdraw(_pid, _wantAmt, msg.sender);
    }

    // For unique contract calls
    function withdraw(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant onlyOperator {
        _withdraw(_pid, _wantAmt, _to);
    }

    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) internal {
        Vault storage pool = vaults[_pid];
        UserBalance storage user = pool.users[msg.sender];

        uint256 wantLockedTotal = pool.strat.wantLockedTotal();
        uint256 sharesTotal = pool.strat.sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        uint256 amount = user.shares * wantLockedTotal / sharesTotal;
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved = pool.strat.withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares -= sharesRemoved;
            }

            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            pool.want.safeTransfer(_to, _wantAmt);
        }
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    function withdrawAll(uint256 _pid) external autoCompound {
        _withdraw(_pid, type(uint256).max, msg.sender);
    }

    function resetAllowances() external onlyOwner {
        for (uint256 i; i < vaults.length; i++) {
            Vault storage pool = vaults[i];
            pool.want.safeApprove(pool.strat, 0);
            pool.want.safeIncreaseAllowance(pool.strat, type(uint256).max);
        }
    }

    function resetSingleAllowance(uint256 _pid) public onlyOwner {
        Vault storage pool = vaults[_pid];
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
    
    
    // Compounding Functionality
    function setCompoundMode(uint mode, bool autoC) external onlyOwner {
        compoundMode = mode;
        autocompoundOn = autoC;
        emit SetCompoundMode(mode, autoC);
    }

    modifier autoCompound {
        if (autocompoundOn && (compoundMode == 0 || operators[msg.sender] || (compoundMode == 1 && msg.sender == tx.origin))) {
            _compoundAll();
        }
        _;
    }

    function compoundAll() external {
        require(compoundMode == 0 || operators[msg.sender] || (compoundMode == 1 && msg.sender == tx.origin), "Compounding is restricted");
        _compoundAll();
    }
    
    function _compoundAll() internal {
        uint numPools = vaults.length;
        for (uint i = 0; i < numPools; i++) {
            try vaults[i].strat.earn() {}
            catch (bytes memory reason) {
                emit CompoundError(i, reason);
            }
        }
    }
}