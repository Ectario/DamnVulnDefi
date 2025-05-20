# Notes

The `PuppetV2Pool` contract calculates the required WETH deposit for borrowing DVT tokens using Uniswap V2 reserve data as a price oracle:

```solidity
function calculateDepositOfWETHRequired(uint256 tokenAmount) public view returns (uint256) {
    uint256 depositFactor = 3;
    return _getOracleQuote(tokenAmount) * depositFactor / 1 ether;
}

function _getOracleQuote(uint256 amount) private view returns (uint256) {
    (uint256 reservesWETH, uint256 reservesToken) =
        UniswapV2Library.getReserves({factory: _uniswapFactory, tokenA: address(_weth), tokenB: address(_token)});

    return UniswapV2Library.quote({amountA: amount * 10 ** 18, reserveA: reservesToken, reserveB: reservesWETH});
}
```

The `quote` function from Uniswap uses the formula (in `UniswapV2Library.sol`):

```
amountB = amountA * reserveB / reserveA
```

Here, `reserveA` is the DVT token, and `reserveB` is WETH. Therefore, the more DVT in the pool (higher `reserveA`), or the less WETH (lower `reserveB`), the cheaper the DVT appears when quoted in WETH.

Because this logic uses the current reserves directly and without averaging, it is vulnerable to manipulation through swaps.

Therefore we need to drain DVT liquidity from the Uniswap pair by swapping all of the DVT for WETH.

some docs used: 

- https://docs.uniswap.org/contracts/v2/reference/smart-contracts/pair#getreserves
- https://docs.uniswap.org/contracts/v2/reference/smart-contracts/router-02