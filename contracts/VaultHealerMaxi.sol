// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./VaultHealer.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract VaultHealerMaxi is VaultHealer {
    
    mapping(address => uint) maxiDebt; //negative maximizer tokens to offset adding to pools, etc
    
    constructor(address _maximizeToken) {
        maxiToken = _maximizeToken;
        //deploy maxi core strategy here
    }
    
    //maximized token balance
    function balanceOf(address account) external view returns (uint) {
        address core = poolInfo[0].strat;
        uint totalShares = IStrategy(core).sharesTotal();
        uint shares = coreShares(account);
        
        return totalShares == 0 ? 0 : shares * IStrategy(core).wantLockedTotal() / totalShares;
    }
    
    //returns a user's share of the maximizer core vault
    function coreShares(address user) public view returns (uint shares) {

        int _shares = int(userInfo[0][user].shares) - int(maxiDebt[user]);
        
        //Add the user's share of each maximizer's share of the core vault
        for (uint i; i < poolInfo.length; i++) {
            _shares += coreSharesFromMaximizer(i, user);
        }
        
        require(_shares >= 0, "ASSERT: user left with net negative coreShares");
        return uint(_shares);
    }
    //for a particular account, shares contributed by one of the maximizers
    function coreSharesFromMaximizer(uint _pid, address _user) internal view returns (int shares) {

        require(_pid > 0 && _pid < poolInfo.length, "ASSERT: coreSharesFromMaximizer bad pid");
        
        int userStratShares = int(userInfo[_pid][_user].shares); //user's share of the maximizer
        
        address strategy = poolInfo[_pid].strat; //maximizer strategy
        int stratCoreShares = int(userInfo[_pid][strategy].shares) - int(maxiDebt[strategy]); // maximizer's share of the core vault, this determines +/-
        int stratSharesTotal = int(IStrategy(strategy).sharesTotal()); //total shares of the maximizer vault
        
        return userStratShares * stratCoreShares / stratSharesTotal;
        
    }
    
    //for maximizer functions to deposit the maximized token in the core vault
    function maximizerDeposit(uint256 _wantAmt) external {
        require(strats[msg.sender], "only callable by strategies");
        super._deposit(0, _wantAmt, msg.sender);
    }

    function _deposit(uint256 _pid, uint256 _wantAmt, address _to) internal override returns (uint sharesAdded) {
        sharesAdded = super._deposit(_pid, _wantAmt, _to);
        if (_pid > 0) {
            //rebalance shares so core shares are the same as before for the individual user and for the rest of the pool
        }
    }
    
    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) internal override returns (uint sharesTotal, uint sharesRemoved) {
        (sharesTotal, sharesRemoved) = super._withdraw(_pid, _wantAmt, _to);
        if (_pid > 0) {
            //rebalance shares so core shares are the same as before for the individual user and for the rest of the pool
        }
    }
}