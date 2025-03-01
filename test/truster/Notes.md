# Notes

In `TrusterLenderPool.sol`:

```solidity
    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data)
        external
        nonReentrant
        returns (bool)
    {
        uint256 balanceBefore = token.balanceOf(address(this));

        token.transfer(borrower, amount);
        target.functionCall(data);

        if (token.balanceOf(address(this)) < balanceBefore) {
            revert RepayFailed();
        }

        return true;
    }
```

At first glance, a reentrancy attack using only this contract does not seem possible due to the **nonReentrant** modifier, which acts as a lock.  

Another security measure is that, at the end of the `flashloan` call, the condition `token.balanceOf(address(this)) < balanceBefore` must always hold true.  

One interesting primitive to keep in mind is that the token contract itself does not have a lock on its functions. This raises the question: Could a cross-contract reentrancy be possible?  

Here are two key observations (one is better than the other-go on, take a wild guess lol):  

- The check at the end of the function, `token.balanceOf(address(this)) < balanceBefore`, does not ensure strict equality but only verifies if the balance is strictly lower. This means that if we somehow "duplicate tokens" and the pool ends up with more funds, the condition still holds. (Though in practice, this might not be useful, but hey, we work with what we have! xD)  

- If this balance check is an obstacle, we don’t necessarily need to bypass it if we have already "backdoored" the token to send it back later. A promising idea is as follows:  
  1. We create a contract that takes a flashloan to send the token to itself.  
  2. We then call our function via `target.functionCall(data);` to approve our contract in the allowances.  
  3. While still in the callback function, our contract transfers the tokens to the pool, completing the flashloan.  
  4. Since the flashloan has ended, we can now use our backdoor (from the allowances) to transfer the tokens back to ourselves-or better yet, send them to the recovery account, as required by the challenge.  