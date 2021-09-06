// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


import "./libs/IStrategy.sol";
import "./Operators.sol";
import "./libs/VaultData.sol";

contract VaultHealer is Ownable, ReentrancyGuard, Operators {
    using VaultData for IERC20;
    using VaultData for VaultInfo;
    using VaultData for Vault;

    VaultInfo internal vaultInfo;
    
    mapping(address => bool) private strats;

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
    event SetFeeConfig(uint indexed config, address[] _receivers, uint16[]  _feeRates, FeeMethod[]  _methods);

    function poolInfo(uint _vid) external view returns (IERC20 want, IStrategy strat) {
        return (vaultInfo.vaults[_vid].want, vaultInfo.vaults[_vid].strat);
    }

    function poolLength() external view returns (uint256) {
        return vaultInfo.vaultsLength;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat) external onlyOwner nonReentrant {
        require(!strats[_strat], "Existing strategy");
        vaultInfo.vaults[vaultInfo.vaultsLength].want = IERC20(IStrategy(_strat).wantAddress());
        vaultInfo.vaults[vaultInfo.vaultsLength].strat = IStrategy(_strat);
        strats[_strat] = true;
        resetSingleAllowance(vaultInfo.vaultsLength);
        vaultInfo.vaultsLength++;
        emit AddPool(_strat);
    }
    function addFeeConfig(address[] calldata _receivers, uint16[] calldata _feeRates, FeeMethod[] calldata _methods) external {
        require(_receivers.length == FEETYPE_LENGTH && _feeRates.length == FEETYPE_LENGTH && _methods.length == FEETYPE_LENGTH, "invalid fee array length");
        vaultInfo.feeConfigs.push();
        uint feeConfigNew = vaultInfo.feeConfigs.length - 1;
        setFeeConfig(feeConfigNew, _receivers, _feeRates, _methods);
    }
    function setFeeConfig(uint _configNum, address[] calldata _receivers, uint16[] calldata _feeRates, FeeMethod[] calldata _methods) public {
        require(_configNum < vaultInfo.feeConfigs.length, "feeconfig must exist to be set");
        require(_receivers.length == FEETYPE_LENGTH && _feeRates.length == FEETYPE_LENGTH && _methods.length == FEETYPE_LENGTH, "invalid fee array length");
        
        vaultInfo.feeConfigs.push();
        uint feeConfigNew = vaultInfo.feeConfigs.length - 1;
        for (uint i; i < FEETYPE_LENGTH; i++) {
            FeeType feeType = FeeType(i);
            vaultInfo.feeConfigs[feeConfigNew].receiver[feeType] = _receivers[i];
            vaultInfo.feeConfigs[feeConfigNew].feeRate[feeType] = _feeRates[i];
            vaultInfo.feeConfigs[feeConfigNew].method[feeType] = _methods[i];
        }
        emit SetFeeConfig(feeConfigNew, _receivers, _feeRates, _methods);
    }

    function stakedWantTokens(uint256 _vid, address _user) external view returns (uint256) {
        (uint cTokens, uint mTokens) = vaultInfo.balance(_vid, _user);
        return cTokens + mTokens;
    }

    function deposit(uint256 _vid, uint256 _wantAmt, uint _maxiPercent) external nonReentrant autoCompound {
        _deposit(_vid, _wantAmt, _maxiPercent, msg.sender);
    }
    // For unique contract calls
    function deposit(uint256 _vid, uint256 _wantAmt, uint _maxiPercent, address _to) external nonReentrant onlyOperator {
        _deposit(_vid, _wantAmt, _maxiPercent, _to);
    }
    
    //_maxiPercent: 1e18 == 100%
    function _deposit(uint256 _vid, uint256 _wantAmt, uint _maxiPercent, address _to) internal {
        Vault storage vault = vaultInfo.vaults[_vid];
        //must update wantLocked before transfer
        vault.wantLocked = vault.strat.wantLockedTotal();
        
        if (_wantAmt > 0) {
            (uint cTokens, uint mTokens) = vault.balance(msg.sender);
            uint userTotalBefore = cTokens + mTokens;
            
            _wantAmt = vault.want.transferFromWithFee(vaultInfo.vaultFees(_vid), FeeType.DEPOSIT, msg.sender, address(vault.strat), _wantAmt);
            
            uint256 tokensAdded = vault.strat.deposit(vault.wantLocked, _wantAmt);
            require(tokensAdded == vault.strat.wantLockedTotal() - vault.wantLocked, "assert: deposit bug");
            //If true, tokens are reallocated to match the desired percentage to maximizer
            bool auth = _to == msg.sender && _maxiPercent != type(uint256).max;
            if (_maxiPercent == type(uint256).max) _maxiPercent = 0;
            vaultInfo.editTokens(_vid, _to, userTotalBefore + tokensAdded, _maxiPercent, auth);
        }
        emit Deposit(_to, _vid, _wantAmt);
    }
    
    function withdrawAll(uint256 _vid) external autoCompound {
        _withdraw(_vid, type(uint256).max, type(uint256).max, msg.sender);
    }
    function withdraw(uint _vid, uint _wantAmt, uint _maxiPercent) external nonReentrant autoCompound {
        _withdraw(_vid, _wantAmt, _maxiPercent, msg.sender);
    }
    // For unique contract calls
    function withdraw(uint _vid, uint _wantAmt, uint _maxiPercent, address _to) external nonReentrant onlyOperator {
        _withdraw(_vid, _wantAmt, _maxiPercent, _to);
    }
    function _withdraw(uint _vid, uint _wantAmt, uint _maxiPercent, address _to) internal {
        Vault storage vault = vaultInfo.vaults[_vid];
        vault.wantLocked = vault.strat.wantLockedTotal();
        
        (uint cTokens, uint mTokens) = vault.balance(msg.sender);
        uint amount = cTokens + mTokens;

        if (_wantAmt == 0 || amount == 0) {
            vaultInfo.editTokens(_vid, msg.sender, amount, _maxiPercent, true);
        } else {
            if (_wantAmt > 0) {
                if (_wantAmt > amount) _wantAmt = amount;
                (uint256 tokensRemoved, uint tokensToTransfer) = vault.strat.withdraw(vault.wantLocked, _wantAmt);
                require(tokensRemoved == vault.wantLocked - vault.strat.wantLockedTotal(), "assert: deposit bug");
                vaultInfo.editTokens(_vid, msg.sender, amount - tokensRemoved, _maxiPercent, true);
                
                vault.want.transferFromWithFee(vaultInfo.vaultFees(_vid), FeeType.WITHDRAW, address(vault.strat), _to, tokensToTransfer);
            }
        }
        emit Withdraw(msg.sender, _vid, _wantAmt);
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
        mapping (uint => Vault) storage vaults = vaultInfo.vaults;
        uint numPools = vaultInfo.vaultsLength;
        for (uint i; i < numPools; i++) {
            try vaults[i].strat.earn(vaults[i].mTokens) {}
            catch (bytes memory reason) {
                emit CompoundError(i, reason);
            }
        }
    }
}