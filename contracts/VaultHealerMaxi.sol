// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./VaultHealer.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract VaultHealerMaxi is VaultHealer {
    using Math for uint256;
    
    mapping(address => uint) maxiDebt; //negative maximizer tokens to offset adding to pools
    
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

        shares = userInfo[0][user].shares;
        
        //Add the user's share of each maximizer's share of the core vault
        for (uint i; i < poolInfo.length; i++) {
            shares += coreSharesFromMaximizer(i, user);
        }
    }
    //for a particular account, shares contributed by one of the maximizers
    function coreSharesFromMaximizer(uint _pid, address _user) internal view returns (uint shares) {

        require(_pid > 0 && _pid < poolInfo.length, "ASSERT: coreSharesFromMaximizer bad pid");
        
        uint userStratShares = userInfo[_pid][_user].shares; //user's share of the maximizer
        
        address strategy = poolInfo[_pid].strat; //maximizer strategy
        uint stratSharesTotal = IStrategy(strategy).sharesTotal(); //total shares of the maximizer vault
        if (stratSharesTotal == 0) return 0;
        uint stratCoreShares = userInfo[_pid][strategy].shares;
        
        return userStratShares * stratCoreShares / stratSharesTotal;
    }
    //subtract debt for core strategy
    function getUserShares(uint256 _pid, address _user) internal view override returns (uint shares) {
        return userInfo[_pid][_user].shares - (_pid == 0 ? maxiDebt[_user] : 0);
    }
    function addUserShares(uint256 _pid, address _user, uint sharesAdded) internal virtual returns (uint shares) {
        if (_pid == 0) {
            
        } else {
            userInfo[_pid][_user].shares += sharesAdded;
            return userInfo[_pid][_user].shares;
        }
    }
    function removeUserShares(uint256 _pid, address _user, uint sharesRemoved) internal virtual returns (uint shares) {
        userInfo[_pid][_user].shares -= sharesRemoved;
        return userInfo[_pid][_user].shares;
    }
    
    //for maximizer functions to deposit the maximized token in the core vault
    function maximizerDeposit(uint256 _wantAmt) external {
        require(strats[msg.sender], "only callable by strategies");
        super._deposit(0, _wantAmt, msg.sender);
    }

    function _deposit(uint256 _pid, uint256 _wantAmt, address _to) internal override returns (uint sharesAdded) {
        address strat = poolInfo[_pid].strat;
        uint256 sharesTotal = IStrategy(strat).sharesTotal(); // must be total before shares are added
        sharesAdded = super._deposit(_pid, _wantAmt, _to);
        if (_pid > 0 && sharesTotal > 0) {
            //rebalance shares so core shares are the same as before for the individual user and for the rest of the pool
            UserInfo storage maxiCoreInfo = userInfo[0][strat]; // core shares held by the maximizer
            
            //old/new == old/new; vault gets +shares, depositor gets -shares but it all evens out
            uint coreShareOffset = (maxiCoreInfo.shares * (sharesTotal + sharesAdded)).ceilDiv(sharesTotal) - maxiCoreInfo.shares; //ceilDiv benefits pool over user preventing abuse
            maxiCoreInfo.shares += coreShareOffset; 
            userInfo[0][_to].shares -= coreShareOffset;
        }
    }
    
    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) internal override returns (uint sharesTotal, uint sharesRemoved) {
        (sharesTotal, sharesRemoved) = super._withdraw(_pid, _wantAmt, _to);
        if (_pid > 0 && sharesTotal > 0) {
            //rebalance shares so core shares are the same as before for the individual user and for the rest of the pool
            address strat = poolInfo[_pid].strat;
            UserInfo storage maxiCoreInfo = userInfo[0][strat]; // core shares held by the maximizer
            
            uint coreShareOffset = maxiCoreInfo.shares - ((sharesTotal - sharesRemoved) * maxiCoreInfo.shares).ceilDiv(sharesTotal); //ceilDiv benefits pool over user preventing abuse
            maxiCoreInfo.shares -= coreShareOffset; 
            userInfo[0][msg.sender].shares += coreShareOffset;
        }
    }
}