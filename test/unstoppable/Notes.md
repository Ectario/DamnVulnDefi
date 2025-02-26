# Notes

The monitor seems to set Pause if the vault flashloan fail.

in `UnstoppableVault.sol` it fails if:

```solidity
    function flashLoan(IERC3156FlashBorrower receiver, address _token, uint256 amount, bytes calldata data)
        external
        returns (bool)
    {
    ...
        if (amount == 0) revert InvalidAmount(0); // fail early
        if (address(asset) != _token) revert UnsupportedCurrency(); // enforce ERC3156 requirement
        uint256 balanceBefore = totalAssets();
        if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance(); // enforce ERC4626 requirement  <----------
    ...
    }
```

The **totalSupply** value isn’t updated when tokens are sent to the vault, whereas the **totalAssets()** function dynamically retrieves the current token balance held by the contract. This means that **totalAssets()** always reflects the real-time ownership of tokens, while **totalSupply** may remain outdated until explicitly refreshed by deposit for example.


## fuzzing test

```solidity
    function invariant_unstoppable_pool_balance_and_supply_check() public view {
        assert(vault.convertToShares(vault.totalSupply()) == token.balanceOf(address(vault)));
    }
```

```sh
[FAIL: invariant_unstoppable_pool_balance_and_supply_check replay failure]
        [Sequence] (original: 1, shrunk: 1)
                sender=0x1240FA2A84dd9157a0e76B5Cfe98B1d52268B264 addr=[src/DamnValuableToken.sol:DamnValuableToken]0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b calldata=transfer(address,uint256) args=[0x6E9c37753b9eF9AFE423CDe2Af11b7E25E27cd20, 6359]
```

## resources

informative behavior about ERC4626 : https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack