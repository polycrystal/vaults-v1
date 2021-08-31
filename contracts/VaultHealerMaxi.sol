// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./VaultHealer.sol";
import "./StrategyMaxiCore.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract VaultHealerMaxi is VaultHealer {
    using Math for uint256;
    
    mapping(address => uint) public maxiDebt; //negative maximizer tokens to offset adding to pools
    
    constructor(
        address _masterchefAddress,
        address _uniRouterAddress,
        uint256 _pid,
        address _wantAddress,
        uint256 _tolerance,
        address[] memory _earnedToWmaticPath,
        address[] memory _earnedToUsdcPath,
        address[] memory _earnedToFishPath
    ) {
        maxiToken = _wantAddress;
        
        StrategyMaxiCore coreStrategy = new StrategyMaxiCore(
            msg.sender, 
            _masterchefAddress,
            _uniRouterAddress,
            _pid,
            _wantAddress,
            _tolerance,
            _earnedToWmaticPath,
            _earnedToUsdcPath,
            _earnedToFishPath
        );
        addPool(address(coreStrategy));
    }
    
    //for a particular account, shares contributed by one of the maximizers
    function coreSharesFromMaximizer(uint _pid, address _user) internal view returns (uint shares) {

        require(_pid > 0 && _pid < poolInfo.length, "VaultHealerMaxi: coreSharesFromMaximizer bad pid");
        
        uint userStratShares = getUserShares(_pid, _user); //user's share of the maximizer
        
        address strategy = poolInfo[_pid].strat; //maximizer strategy
        uint stratSharesTotal = IStrategy(strategy).sharesTotal(); //total shares of the maximizer vault
        if (stratSharesTotal == 0) return 0;
        uint stratCoreShares = getUserShares(_pid, strategy);
        
        return userStratShares * stratCoreShares / stratSharesTotal;
    }
    function getUserShares(uint256 _pid, address _user) internal view override returns (uint shares) {
        
        shares = super.getUserShares(0, _user);
        
        if (_pid == 0 && !strats[_user]) {
            //Add the user's share of each maximizer's share of the core vault
            for (uint i = 1; i < poolInfo.length; i++) {
                shares += coreSharesFromMaximizer(i, _user);
            }
            shares -= maxiDebt[_user];
        }
    }
    function removeUserShares(uint256 _pid, address _user, uint sharesRemoved) internal override returns (uint shares) {
        if (_pid == 0 && !strats[_user] && sharesRemoved > super.getUserShares(0, _user)) {
            maxiDebt[_user] += sharesRemoved;
            return getUserShares(_pid, _user);
        } else {
            return super.removeUserShares(_pid, _user, sharesRemoved);
        }
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
            uint maxiCoreShares = getUserShares(0, strat); // core shares held by the maximizer
            
            //old/new == old/new; vault gets +shares, depositor gets -shares but it all evens out
            uint coreShareOffset = (maxiCoreShares * (sharesTotal + sharesAdded)).ceilDiv(sharesTotal) - maxiCoreShares; //ceilDiv benefits pool over user preventing abuse
            addUserShares(0, strat, coreShareOffset); 
            removeUserShares(0, _to, coreShareOffset);
        }
    }
    
    function _withdraw(uint256 _pid, uint256 _wantAmt, address _to) internal override returns (uint sharesTotal, uint sharesRemoved) {
        (sharesTotal, sharesRemoved) = super._withdraw(_pid, _wantAmt, _to);
        if (_pid > 0 && sharesTotal > 0) {
            //rebalance shares so core shares are the same as before for the individual user and for the rest of the pool
            address strat = poolInfo[_pid].strat;
            uint maxiCoreShares = getUserShares(0, strat); // core shares held by the maximizer
            
            uint coreShareOffset = maxiCoreShares - ((sharesTotal - sharesRemoved) * maxiCoreShares).ceilDiv(sharesTotal); //ceilDiv benefits pool over user preventing abuse
            removeUserShares(0, strat, coreShareOffset); 
            addUserShares(0, _to, coreShareOffset);
        }
    }
}