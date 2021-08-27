// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./VaultHealer.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract VaultHealerMaxi is VaultHealer {
    
    mapping(address => uint) maxiDebt; //negative maximizer tokens to offset adding to pools, etc
    
    constructor(address _maximizeToken) {
        maximizeToken = _maximizeToken;
        //deploy maxi core strategy here
    }
    
    //maximized token balance
    function balanceOf(address account) external view returns (uint) {
        address core = poolInfo[0].strat;
        uint totalShares = IStrategy(core).sharesTotal();
        int shares = coreShares(account);
        if (shares <= 0 || totalShares == 0) return 0;
        
        return uint(shares) * IStrategy(core).wantLockedTotal() / totalShares;
    }
    
    //returns a user's share of the maximizer core vault
    function coreShares(address user) public view returns (int shares) {

        shares = int(userInfo[0][user].shares) - int(maxiDebt[user]);
        
        //Add the user's share of each maximizer's share of the core vault
        for (uint i; i < poolInfo.length; i++) {
            shares += coreSharesFromMaximizer(i, user);
        }
    }
    //for a particular account, shares contributed by one of the maximizers
    function coreSharesFromMaximizer(uint _pid, address _user) internal view returns (int shares) {

        assert(_pid > 0 && _pid < poolInfo.length);
        
        int userStratShares = int(userInfo[_pid][_user].shares); //user's share of the maximizer
        
        address strategy = poolInfo[_pid].strat; //maximizer strategy
        int stratCoreShares = int(userInfo[_pid][strategy].shares) - int(maxiDebt[strategy]); // maximizer's share of the core vault, this determines +/-
        int stratSharesTotal = int(IStrategy(strategy).sharesTotal()); //total shares of the maximizer vault
        
        return userStratShares * stratCoreShares / stratSharesTotal;
        
    }
    
    //for maximizer functions to deposit the maximized token in the core vault
    function maximizerDeposit(uint256 _wantAmt) external {
        require(pidLookup[msg.sender] != 0, "only callable by strategies"); //0 is either core which shouldn't call this, or something unwelcome
        super._deposit(0, _wantAmt, msg.sender);
    }
    
}