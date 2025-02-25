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


## resources

informative behavior about ERC4626 : https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack