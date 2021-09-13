// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./IStrategyCore.sol";

struct MCore {

    IStrategyCore strat;    
    IERC20 want;
    
    uint wantLocked;
    uint cShares;
    
    mapping (address => int) userShares;
    mapping (uint => uint) maximizerShares; //shares owned by vaults
}

struct Vault {
    uint vid; // vault id number; if in an array should match the index
    IStrategy strat; //contract address
    IERC20 want;   //deposited token
    
    uint wantLocked; //last known wantLockedTotal
    uint cShares; //total compounding shares
    uint mTokens; //total locked tokens whose earnings are directed to the maximizer core

    mapping (address => UserBalance) users;
    
}
struct UserBalance {
    uint cShares;
    uint mTokens;
    uint192 mPercent; // saved setting for allocation to maximiser; frontend can use this for a slider default
    uint64 lastEditBlock;
}
struct MaximizerSettings {
    uint64 min;
    uint64 _default;
    uint64 max;
}

library VaultData {
    using SafeERC20 for IERC20;
    using Math for uint256;
    
    //user maximizer core token deposit, including maximizer shares
    function balance(MCore storage _mCore, Vault[] storage _vaults, address _user) internal view returns (uint) {
     
        if (_mCore.cShares == 0 || _mCore.wantLocked == 0) return 0;
        
        uint shares;
        for (uint i; i < _vaults.length; i++) { //for each vault
            Vault storage vault = _vaults[i];
            uint mTokens = vault.users[_user].mTokens; //count the user's tokens 
            if (mTokens == 0) continue;
            shares += mTokens * _mCore.maximizerShares[i] / vault.mTokens; // user's share of each maximizer, weighted by each vault's share of the core
        }
        int userShares = _mCore.userShares[_user];
        shares = userShares >= 0 ? shares + uint(userShares) : shares - uint(-userShares);
        return shares * _mCore.wantLocked / _mCore.cShares;
    }
    //for maximizer deposits to core
    function deposit(MCore storage _mCore, uint _vid, uint _amount) internal {
        if (_mCore.wantLocked > 0) _amount = _amount * _mCore.cShares / _mCore.wantLocked;
        _mCore.maximizerShares[_vid] += _amount;
        _mCore.cShares += _amount;
    }
    //for user deposits to core
    function deposit(MCore storage _mCore, address _user, uint _amount) internal {
        if (_mCore.wantLocked > 0) _amount = _amount * _mCore.cShares / _mCore.wantLocked;
        _mCore.userShares[_user] += int(_amount);
        _mCore.cShares += _amount;
    }
    //for user withdrawals from core
    function withdraw(MCore storage _mCore, Vault[] storage _vaults, address _user, uint _amount) internal {
        require(balance(_mCore, _vaults, _user) >= _amount, "Insufficient core balance for withdrawal");
        _amount = (_amount * _mCore.cShares).ceilDiv(_mCore.wantLocked);
        _mCore.userShares[_user] -= int(_amount);
        _mCore.cShares -= _amount;
    }
    
    function balance(Vault storage _vault, address _user) internal view returns (uint cTokens, uint mTokens) {
        if (_vault.cShares > 0) cTokens = _vault.wantLocked * _vault.users[_user].cShares / _vault.cShares;
        mTokens = _vault.users[_user].mTokens;
    }
    
    
    function editTokens(
        Vault storage _vault,
        MCore storage _mCore,
        address _user,
        uint _userTokensAfter,
        uint _mPercent, // ratio/1e18 allocated to mTokens
        bool _auth // allowed to allocate user cShares/mTokens below current values?
    ) internal {
        UserBalance storage user = _vault.users[_user];
        if (_mPercent == type(uint).max) _mPercent = user.mPercent;
        require(_mPercent <= 1e18, "1e18 = max/100%"); // 1e18 = 100%
        if (_auth) {
            require(block.timestamp > user.lastEditBlock, "one action per vault per block");
            user.mPercent = uint64(_mPercent);
            user.lastEditBlock = uint64(block.timestamp);
        }
        //token totals before deposit
        uint mTokensBefore = _vault.mTokens;

        //user token balances before deposit
        uint cUserTokensBefore = _vault.cShares == 0 ? 0 : _vault.wantLocked * _vault.users[_user].cShares / _vault.cShares;
        uint mUserTokensBefore = _vault.users[_user].mTokens;
        uint userTokensBefore = cUserTokensBefore + mUserTokensBefore;
        require (_auth || _userTokensAfter >= userTokensBefore, "withdrawal must be authorized");
        
        //allocate tokens to the desired ratio, but don't move previously deposited tokens unless _auth is true
        uint mUserTokens = _mPercent * _userTokensAfter / 1e18;
        uint cUserTokens = _userTokensAfter - mUserTokens;
        if (!_auth && cUserTokens < cUserTokensBefore) { //would lose cTokens so we simply add to mTokens
            user.mTokens = user.mTokens + _userTokensAfter - userTokensBefore;
            _vault.mTokens = _vault.mTokens + _userTokensAfter - userTokensBefore;
        } else if (!_auth && mUserTokens < mUserTokensBefore) { //would lose mTokens so we simply add to cTokens
            uint sharesAdded = _userTokensAfter - userTokensBefore;
            if (_vault.cShares > 0) sharesAdded = sharesAdded * _vault.cShares / (_vault.wantLocked - mTokensBefore);
            user.cShares += sharesAdded;
            _vault.cShares += sharesAdded;
        } else {    //free to allocate as directed
            user.mTokens = mUserTokens;
            _vault.mTokens = _vault.mTokens + mUserTokens - mUserTokensBefore;
            if (cUserTokens >= cUserTokensBefore) {
                uint sharesAdded = cUserTokens - cUserTokensBefore;
                uint cTokensBefore = _vault.wantLocked - mTokensBefore;
                if (_vault.cShares > 0) sharesAdded = sharesAdded * _vault.cShares / cTokensBefore;
                user.cShares += sharesAdded;
                _vault.cShares += sharesAdded;
            } else {
                uint sharesRemoved = ((cUserTokensBefore - cUserTokens) * _vault.cShares).ceilDiv(_vault.wantLocked - mTokensBefore);
                _vault.cShares -= sharesRemoved;
                user.cShares -= sharesRemoved;
            }
        }
        
        //balance shares of core owned by user/maximizer vault
        if (mTokensBefore > 0 && mTokensBefore != _vault.mTokens) {
            uint maxiCoreSharesBefore = _mCore.maximizerShares[_vault.vid];
            //shares per token remain the same in the vault
            _mCore.maximizerShares[_vault.vid] = (_vault.mTokens * maxiCoreSharesBefore).ceilDiv(mTokensBefore);
            //assign the difference to the user's balance
            _mCore.userShares[_user] += int(maxiCoreSharesBefore) - int(_mCore.maximizerShares[_vault.vid]);
        }
        
    }
}