// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./StrategyData.sol";
import "./IStrategy.sol";

library ShareBalancer {

/*

Here we rely on the fact that mShares are the portion that doesn't autocompound. By subtracting them from calculations we can determine values for cShares.

    struct Balances {
        uint256 cSharesTotal;
        uint256 mTokensTotal;
        mapping (address => UserData) users;
    }
    struct UserData {
        uint cShares;
        uint mTokens;
    }
*/

    function addTokens(
            StrategyData.Balances storage _bal,
            address _strat, // strategy address
            address _user,
            uint _tokensAdded,
            uint _mPercentTotal, // ratio/1e18 allocated to mTokens
            bool _auth // allowed to allocate user cShares/mTokens below current value to reach correct percent?
        ) internal {
        
        require(_cPercent <= 1e18, "1e18 = max/100%"); // 1e18 = 100%
        
        StrategyData.UserData storage user = _bal.users[_user];

        //token totals before deposit
        uint mTokensBefore = _bal.mTokensTotal;
        uint cTokensBefore = IStrategy(_strat).wantLockedTotal() - _tokensAdded - mTokensBefore;
        
        //user's share in compounder, before deposit
        uint cUserSharesBefore = user.cShares;
        uint cUserTokensBefore = cUserSharesBefore * cTokensBefore / _bal.cSharesTotal;
        
        uint userTokensBefore = user.mTokens + cUserTokensBefore;


        //after deposit, user owns this amount of tokens in vault
        uint userTokensAfter = userTokensBefore + _tokensAdded;
        
        //allocate tokens to the desired ratio, but don't move around previously deposited tokens unless _auth is true
        uint cUserTokens = _cPercent * userTokensAfter / 1e18;
        uint mUserTokens = userTokensAfter - cUserTokens;
        if (!_auth && cUserTokens > cUserTokensBefore + _tokensAdded) {
            cUserTokens = cUserTokensBefore + _tokensAdded;
            mUserTokens = mUserTokensBefore;
        } else if (!_auth && mUserTokens > mUserTokensBefore + _tokensAdded) { 
            cUserTokens = cUserTokensBefore;
            mUserTokens = mUserTokensBefore + _tokensAdded;
        }
        
        //calculate and set new share amounts
        user.cShares = cUserTokens * _bal.cSharesTotal / cTokensBefore;
        user.mTokens = mUserTokens;
        _bal.cSharesTotal = _bal.cSharesTotal + user.cShares - cUserSharesBefore;
        _bal.mTokensTotal = mTokensBefore + user.mTokens - mUserTokensBefore;
    }
    
    function removeTokens(
            StrategyData.Balances storage _bal,
            address _strat, // strategy address
            address _user,
            uint _tokensRemoved,
            uint _cPercent // ratio/1e18 allocated to cShares
    ) internal {
        
        require(_cPercent <= 1e18, "1e18 = max/100%"); // 1e18 = 100%
        
        StrategyData.UserData storage user = _bal.users[_user];

        //token totals before deposit
        uint mTokensBefore = _bal.mTokensTotal;
        uint cTokensBefore = IStrategy(_strat).wantLockedTotal() + _tokensRemoved - mTokensBefore;
        
        //user's shares in compounder and maximizer, before withdrawal
        uint cUserSharesBefore = user.cShares;
        uint mUserSharesBefore = user.mShares;
        
        //token equivalent of the user's shares
        uint mUserTokensBefore = mUserSharesBefore * mTokensBefore / _bal.mSharesTotal;
        uint cUserTokensBefore = cUserSharesBefore * cTokensBefore / _bal.cSharesTotal;
        uint userTokensBefore = mUserTokensBefore + cUserTokensBefore;

        //after withdrawal, user owns this amount of tokens in vault
        uint userTokensAfter = userTokensBefore - _tokensRemoved;
        
        //allocate tokens to the desired ratio
        uint cUserTokens = _cPercent * userTokensAfter / 1e18;
        uint mUserTokens = userTokensAfter - cUserTokens;
        
        //calculate and set new share amounts
        user.cShares = cUserTokens * _bal.cSharesTotal / cTokensBefore;
        user.mShares = mUserTokens * _bal.mSharesTotal / mTokensBefore;
        _bal.cSharesTotal = _bal.cSharesTotal - cUserSharesBefore + user.cShares;
        _bal.mSharesTotal = _bal.mSharesTotal - mUserSharesBefore + user.mShares;
        _bal.mTokensTotal = mTokensBefore - mUserTokensBefore + mUserTokens;
    }
    
}