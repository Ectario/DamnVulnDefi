# Notes

By converting hex to ASCII, then decoding the ASCII (which looks like base64), we get:

```bash
echo "MHg3ZDE1YmJhMjZjNTIzNjgzYmZjM2RjN2NkYzVkMWI4YTI3NDQ0NDc1OTdjZjRkYTE3MDVjZjZjOTkzMDYzNzQ0MHg2OGJkMDIwYWQxODZiNjQ3YTY5MWM2YTVjMGMxNTI5ZjIxZWNkMDlkY2M0NTI0MTQwMmFjNjBiYTM3N2M0MTU5" | base64 -d
```

We get the following output:

```
0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c9930637440x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159
```

Splitting it gives:

```
0x7d15bba26c523683bfc3dc7cdc5d1b8a2744447597cf4da1705cf6c993063744
0x68bd020ad186b647a691c6a5c0c1529f21ecd09dcc45241402ac60ba377c4159
```

These are likely **private keys**.

Given the challenge description:

> "This price is fetched from an on-chain oracle, based on 3 trusted reporters: 0x188...088, 0xA41...9D8 and 0xab3...a40."

It’s very likely that these are the private keys of **two of the trusted reporters**. So we can manipulate the price in our favor — buying the DVNFTs at a low price and reselling them at a high price to drain the exchange.

The function that appears to be responsible for posting prices is:

```solidity
function postPrice(string calldata symbol, uint256 newPrice) external onlyRole(TRUSTED_SOURCE_ROLE) {
    _setPrice(msg.sender, symbol, newPrice);
}
```

By using the leaked private keys to impersonate trusted sources, we can call this function to arbitrarily set prices.