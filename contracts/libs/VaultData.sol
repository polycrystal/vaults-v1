// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./IStrategy.sol";
import "./IApePair.sol";

struct VaultInfo {
    MCore mCore; //maximizer core data
    mapping (uint => Vault) vaults; // "vid" is indices of this array
    uint vaultsLength;
    FeeConfig[] feeConfigs;
    VaultConfig defaultConfig;
}

struct MCore {
    
    IERC20 want;
    IStrategy strat;
    
    uint wantLocked;
    uint cShares;
    
    mapping (address => int) userShares;
//    mapping (uint => uint) maxiShares;
    
    uint8 feeConfig;
}

struct Vault {
    IERC20 want;   //deposited token
    IStrategy stratProxy; //proxy address that holds the tokens
    address stratLogic; //logic implementation for the strategy
    
    uint wantLocked; //last known wantLockedTotal
    uint cShares; //total compounding shares
    uint mTokens; //total locked tokens whose earnings are directed to the maximizer core

    mapping (address => UserBalance) users;

    uint maxiCoreShares; //shares of maximizer core owned by this vault
    
    uint feeConfig;
    
    VaultConfig config;
    
}

struct VaultConfig {
    uint160 minEarn;
    uint32 blocksBetweenEarns;
    uint64 lastEarnBlock;
    address uniRouterAddress;
    uint8 paused;
    uint8 tolerance;
    uint64 panicTimelock;
}

struct UserBalance {
    uint cShares;
    uint mTokens;
    uint64 mPercent; // frontend can use this for a slider default
    uint64 lastEditBlock;
}

enum FeeType { DEPOSIT, WITHDRAW, BUYBACK, CONTROL, REWARD, MISC }
uint constant FEETYPE_LENGTH = 6;
enum FeeMethod {
    PUSH, // transfer tokens to fee receiver
    PUSH_CALL // transfer tokens to fee receiver, then call function
}

struct FeeConfig {
    mapping (FeeType => address) receiver;
    mapping (FeeType => uint16) feeRate;
    mapping (FeeType => FeeMethod) method;
}

interface IFeeReceiver {
    
    function notifyFeePaid(address _token, uint _amount, FeeType _feeType) external;
}


uint constant BASIS_POINTS = 10000;

library VaultData {
    using Math for uint256;
    using SafeERC20 for IERC20;
    
    //user maximizer core token deposit, including maximizer shares
    function coreBalance(VaultInfo storage _vaultInfo, address _user) internal view returns (uint amount) {
        MCore storage mCore = _vaultInfo.mCore;
        mapping (uint => Vault) storage vaults = _vaultInfo.vaults;
        
        for (uint i; i < _vaultInfo.vaultsLength; i++) {
            uint mTokens = vaults[i].users[_user].mTokens;
            if (mTokens == 0) continue;
            amount += mTokens * vaults[i].maxiCoreShares * mCore.wantLocked / vaults[i].mTokens;
        }
        amount /= mCore.cShares;
        
        if (mCore.cShares > 0) {
            int _amount = int(amount) + mCore.userShares[_user] * int(mCore.wantLocked) / int(mCore.cShares);
            require (_amount >= 0, "assert: User core shares can't be negative");
            amount = uint(_amount);
        }
    }
    //for maximizer deposits to core
    function coreDeposit(VaultInfo storage _vaultInfo, uint _vid, uint _amount) internal {
        MCore storage mCore = _vaultInfo.mCore;
        if (mCore.cShares > 0) _amount = _amount * mCore.cShares / mCore.wantLocked;
        _vaultInfo.vaults[_vid].maxiCoreShares += _amount;
        mCore.cShares += _amount;
    }
    //for user deposits to core
    function coreDeposit(VaultInfo storage _vaultInfo, address _user, uint _amount) internal {
        MCore storage mCore = _vaultInfo.mCore;
        if (mCore.cShares > 0) _amount = _amount * mCore.cShares / mCore.wantLocked;
        mCore.userShares[_user] += int(_amount);
        mCore.cShares += _amount;
    }
    //for user withdrawals from core
    function coreWithdraw(VaultInfo storage _vaultInfo, address _user, uint _amount) internal {
        require(coreBalance(_vaultInfo, _user) >= _amount, "Insufficient core balance for withdrawal");
        MCore storage mCore = _vaultInfo.mCore;
        _amount = (_amount * mCore.cShares).ceilDiv(mCore.wantLocked);
        mCore.userShares[_user] -= int(_amount);
        mCore.cShares -= _amount;
    }
    //for user to user transfers
    function coreTransfer(VaultInfo storage _vaultInfo, address _from, address _to, uint _amount) internal {
        require(coreBalance(_vaultInfo, _from) >= _amount, "Insufficient core balance for transfer");
        MCore storage mCore = _vaultInfo.mCore;
        int sharesTransferred = int((_amount * mCore.cShares).ceilDiv(mCore.wantLocked));
        mCore.userShares[_from] -= sharesTransferred;
        mCore.userShares[_to] += sharesTransferred;
    }
    
    function balance(Vault storage _vault, address _user) internal view returns (uint cTokens, uint mTokens) {
        if (_vault.cShares > 0) cTokens = _vault.wantLocked * _vault.users[_user].cShares / _vault.cShares;
        mTokens = _vault.users[_user].mTokens;
    }
    function balance(VaultInfo storage _vaultInfo, uint _vid, address _user) internal view returns (uint cTokens, uint mTokens) {
        return balance(_vaultInfo.vaults[_vid], _user);
    }
    
    
    function editTokens(
        VaultInfo storage _vaultInfo,
        uint _vid,
        address _user,
        uint _userTokensAfter,
        uint _mPercent, // ratio/1e18 allocated to mTokens
        bool _auth // allowed to allocate user cShares/mTokens below current values?
    ) internal {
        Vault storage vault = _vaultInfo.vaults[_vid];
        UserBalance storage user = vault.users[_user];
        if (_mPercent == type(uint).max) _mPercent = user.mPercent;
        require(_mPercent <= 1e18, "1e18 = max/100%"); // 1e18 = 100%
        require(block.timestamp > user.lastEditBlock, "one action per vault per block");
        if (_auth) {
            user.mPercent = uint64(_mPercent);
            user.lastEditBlock = uint64(block.timestamp);
        }
        //token totals before deposit
        uint mTokensBefore = vault.mTokens;
        //uint cTokensBefore = vault.wantLocked - mTokensBefore 

        //user token balances before deposit
        uint cUserTokensBefore = vault.cShares == 0 ? 0 : vault.wantLocked * vault.users[_user].cShares / vault.cShares;
        uint mUserTokensBefore = vault.users[_user].mTokens;
        uint userTokensBefore = cUserTokensBefore + mUserTokensBefore;
        require (_auth || _userTokensAfter >= userTokensBefore, "withdrawal must be authorized");
        
        //allocate tokens to the desired ratio, but don't move previously deposited tokens unless _auth is true
        uint mUserTokens = _mPercent * _userTokensAfter;
        uint cUserTokens = _userTokensAfter - mUserTokens;
        if (!_auth && cUserTokens < cUserTokensBefore) { //would lose cTokens so we simply add to mTokens
            user.mTokens = user.mTokens + _userTokensAfter - userTokensBefore;
            vault.mTokens = vault.mTokens + _userTokensAfter - userTokensBefore;
        } else if (!_auth && mUserTokens < mUserTokensBefore) { //would lose mTokens so we simply add to cTokens
            uint sharesAdded = _userTokensAfter - userTokensBefore;
            if (vault.cShares > 0) sharesAdded = sharesAdded * vault.cShares / (vault.wantLocked - mTokensBefore);
            user.cShares += sharesAdded;
            vault.cShares += sharesAdded;
        } else {    //free to allocate as directed
            user.mTokens = mUserTokens;
            vault.mTokens = vault.mTokens + mUserTokens - mUserTokensBefore;
            if (cUserTokens >= cUserTokensBefore) {
                uint sharesAdded = cUserTokens - cUserTokensBefore;
                if (vault.cShares > 0) sharesAdded = sharesAdded * vault.cShares / (vault.wantLocked - mTokensBefore);
                user.cShares += sharesAdded;
                vault.cShares += sharesAdded;
            } else {
                uint sharesRemoved = ((cUserTokensBefore - cUserTokens) * vault.cShares).ceilDiv(vault.wantLocked - mTokensBefore);
                vault.cShares -= sharesRemoved;
                user.cShares -= sharesRemoved;
            }
        }
        
        //balance shares of core owned by user/maximizer vault
        if (mTokensBefore > 0 && mTokensBefore != vault.mTokens) {
            uint maxiCoreSharesBefore = vault.maxiCoreShares;
            //shares per token remain the same in the vault
            vault.maxiCoreShares = (vault.mTokens * maxiCoreSharesBefore).ceilDiv(mTokensBefore);
            //assign the difference to the user's balance
            _vaultInfo.mCore.userShares[_user] += int(maxiCoreSharesBefore) - int(vault.maxiCoreShares);
        }
        
    }
    function coreFees(VaultInfo storage _vaultInfo) internal view returns (FeeConfig storage fees) {
        fees = _vaultInfo.feeConfigs[_vaultInfo.mCore.feeConfig];
    }
    function vaultFees(VaultInfo storage _vaultInfo, uint _vid) internal view returns (FeeConfig storage fees) {
        fees = _vaultInfo.feeConfigs[_vaultInfo.vaults[_vid].feeConfig];
    }
    function transferFromWithFee(IERC20 _token, FeeConfig storage _feeConfig, FeeType _feeType, address _from, address _to, uint _amount) internal returns (uint amountAfterFee) {
        
        address receiver = _feeConfig.receiver[_feeType];
        uint feeRate = _feeConfig.feeRate[_feeType];
        FeeMethod method = _feeConfig.method[_feeType];
        
        uint feeAmount = (_amount * feeRate).ceilDiv(BASIS_POINTS);
        
        if (feeAmount > 0) {
            _token.safeTransferFrom(_from, _to, feeAmount);
            if (method == FeeMethod.PUSH_CALL) IFeeReceiver(receiver).notifyFeePaid(address(_token), feeAmount, _feeType);
        }
        
        amountAfterFee = _amount - feeAmount;
        _token.safeTransferFrom(_from, _to, amountAfterFee);
    }
}