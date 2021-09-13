// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./IStrategy.sol";

struct VaultInfo {
    MCore mCore; //maximizer core data
    mapping (uint => Vault) vaults; // "vid" is indices of this array
    uint vaultsLength;
}

struct MCore {
    
    IERC20 want;
    IStrategy strat;
    
    uint wantLocked;
    uint cShares;
    
    mapping (address => int) userShares;
    
    uint8 feeConfig;
}

struct Vault {
    IERC20 want;   //deposited token
    
    uint wantLocked; //last known wantLockedTotal
    uint cShares; //total compounding shares
    uint mTokens; //total locked tokens whose earnings are directed to the maximizer core

    mapping (address => UserBalance) users;

    uint maxiCoreShares; //shares of maximizer core owned by this vault
    
}
struct UserBalance {
    uint cShares;
    uint mTokens;
    uint192 mPercent; // saved setting for allocation to maximiser; frontend can use this for a slider default
    uint64 lastEditBlock;
}

library VaultData {
    using SafeERC20 for IERC20;
    using Math for uint256;
    
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
            assert(_amount >= 0);
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
        if (_auth) {
            require(block.timestamp > user.lastEditBlock, "one action per vault per block");
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
        uint mUserTokens = _mPercent * _userTokensAfter / 1e18;
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
}