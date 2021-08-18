# PolyCrystal Vaults
The official repository of PolyCrystal.Finance vault code ❤️🔮

Use them now at [PolyCrystal.Finance/Vaults](https://polycrystal.finance/vaults)!

## Contracts

### VaultHealer
The primary contract which handles user balances and user interactions is the VaultHealer contract, which works as a "MasterChef" of sorts for each one of the vaults.

`VaultHealer: 0xDB48731c021bdB3d73Abb771B4D7aF0F43C0aC16`

### Strategies
Additionally, this VaultHealer contract has a set of strategies (one for each specific vault). This list will be ever-growing as additional vaults are added, so the full list won't be included here. The full list can always be queried on the [VaultHealer contract directly](https://polygonscan.com/address/0xDB48731c021bdB3d73Abb771B4D7aF0F43C0aC16#readContract).

## Vault Security

PolyCrystal's Vaults are a direct fork of [PolyCat.Finance's Vault2 Contracts](https://github.com/polycatfi/polycat-contracts/tree/master/Vault2) with some minor, audited optimizations & necessary configuration changes in place. None of these optimizations alter the flow of funds or how account balances are managed.

We chose this approach since the original vaulting contracts were well-audited and battled tested. We believe time in the market is the biggest tell for the security of a contract, hence the forking approach.

### Contract Alterations
Below are the specific details about each contract used and alternations associated (if any). Clean-up work (such as variable name changes, comments, or import paths) will not be individually specified, but can be seen in the diff-check linked.

- [VaultHealer.sol](https://www.diffchecker.com/hxjHmDf8) - The addition of optional autocompounding functionality of all vaults for each withdraw or deposit. This is to increase the efficiency of compounding. This functionality is able to be toggled off by the owner, if we ever need to revert to the original compounding approach. This piece of code was part of an internal audit by CryptExLocker, and was the largest change to any of the contracts.
- [BaseStrategy.sol](https://www.diffchecker.com/auvehlHF) - Configuration changes. The addition of two read-only variable for front end optimization `tolerance` and `burnAmount`.
- BaseStrategyLP.sol - No changes.
- [BaseStrategyLPSingle.sol](https://www.diffchecker.com/0oQ9IhvW) - Changed `earn()` function modifier from `onlyGov` to `onlyOwner` so VaultHealer contract can effectively call the autocompounding strategy.
- Operators.sol - No changes.
- [StrategyMasterHealer.sol](https://www.diffchecker.com/3f0TaHLB) - File name change from StrategyMasterChef.sol. Inclusion of `tolerance` read-only variable.