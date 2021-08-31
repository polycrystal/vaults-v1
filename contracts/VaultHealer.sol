// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Operators.sol";
import "./libs/IStrategy.sol";

contract VaultHealer is ReentrancyGuard, Operators {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        IERC20 want;
        address strat;
    }

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => uint256)) private userShares;
    mapping(address => bool) public strats;

    // Compounding Variables
    // 0: compound by anyone; 1: EOA only; 2: restricted to operators
    uint public compoundMode = 1;
    bool public autocompoundOn = true;

    address public maxiToken; //Unused/zero unless this is a maximizer VaultHealer

    event AddPool(address indexed strat);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetCompoundMode(uint locked, bool automatic);
    event CompoundError(uint pid, bytes reason);

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) public onlyOwner nonReentrant {
        require(!strats[_strat], "Existing strategy");
        poolInfo.push(
            PoolInfo({
                want: IERC20(IStrategy(_strat).wantAddress()),
                strat: _strat
            })
        );
        strats[_strat] = true;
        resetSingleAllowance(poolInfo.length - 1);
        emit AddPool(_strat);
    }

    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return getUserShares(_pid, _user) * wantLockedTotal / sharesTotal;
    }

    function deposit(uint256 _pid, uint256 _wantAmt) external nonReentrant autoCompound {
        _deposit(_pid, _wantAmt, msg.sender);
    }

    // For unique contract calls
    function deposit(uint256 _pid, uint256 _wantAmt, address _to) external nonReentrant onlyOperator {
        _deposit(_pid, _wantAmt, _to);
    }
    
    //getter and setter are overriden to enable maximizers    
    function userInfo(uint256 _pid, address _user) external view returns (uint) {
        return getUserShares(_pid, _user);
    }
    function getUserShares(uint256 _pid, address _user) internal view virtual returns (uint shares) {
        return userShares[_pid][_user];
    }
    function addUserShares(uint256 _pid, address _user, uint sharesAdded) internal virtual returns (uint shares) {
        userShares[_pid][_user] += sharesAdded;
        return userShares[_pid][_user];
    }
    function removeUserShares(uint256 _pid, address _user, uint sharesRemoved) internal virtual returns (uint shares) {
        userShares[_pid][_user] -= sharesRemoved;
        return userShares[_pid][_user];
    }
    
    function _deposit(uint256 _pid, uint256 _wantAmt, address _to) internal virtual returns (uint sharesAdded) {
        PoolInfo storage pool = poolInfo[_pid];

        if (_wantAmt > 0) {
            pool.want.safeTransferFrom(msg.sender, address(this), _wantAmt);

            sharesAdded = IStrategy(poolInfo[_pid].strat).deposit(_to, _wantAmt);
            addUserShares(_pid, _to, sharesAdded);
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
    
    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) internal virtual returns (uint sharesTotal, uint sharesRemoved) {
        PoolInfo storage pool = poolInfo[_pid];
        uint _userShares = getUserShares(_pid, msg.sender);

        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();

        require(_userShares > 0, "userShares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        uint256 amount = _userShares * wantLockedTotal / sharesTotal;
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            sharesRemoved = IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > _userShares) {
                removeUserShares(_pid, msg.sender, _userShares);
            } else {
                removeUserShares(_pid, msg.sender, sharesRemoved);
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
        for (uint256 i=0; i<poolInfo.length; i++) {
            PoolInfo storage pool = poolInfo[i];
            pool.want.safeApprove(pool.strat, uint256(0));
            pool.want.safeIncreaseAllowance(pool.strat, type(uint256).max);
        }
    }

    function resetSingleAllowance(uint256 _pid) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        pool.want.safeApprove(pool.strat, uint256(0));
        pool.want.safeIncreaseAllowance(pool.strat, type(uint256).max);
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
        uint numPools = poolInfo.length;
        for (uint i; i < numPools; i++) {
            try IStrategy(poolInfo[i].strat).earn() {}
            catch (bytes memory reason) {
                emit CompoundError(i, reason);
            }
        }
    }
}