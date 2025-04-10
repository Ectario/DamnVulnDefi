# Notes

In `SideEntranceLenderPool.sol`:

```solidity
    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;

        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        if (address(this).balance < balanceBefore) {
            revert RepayFailed();
        }
    }
```

The `flashLoan` function has no `nonReentrant` modifier or locking mechanism.  
It’s likely possible to abuse the `deposit()` function during the flash loan to avoid changing the pool’s actual balance, thus bypassing the repayment check.

```solidity
    function deposit() external payable {
        unchecked {
            balances[msg.sender] += msg.value;
        }
        emit Deposit(msg.sender, msg.value);
    }
```

