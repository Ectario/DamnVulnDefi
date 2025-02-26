# Notes

### Analysis of FlashLoanReceiver.sol  

In `FlashLoanReceiver.sol`, the function:  

```solidity
function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
```
The first parameter is unused and not validated, allowing us to impersonate the receiver for the flash loan. This means we can manipulate the transaction to make the receiver pay the fees as we want, which could be crucial for eventually draining the pool.  

Key Observations:

- We need to execute the exploit in two or fewer transactions.  
- The flash loan fee is fixed at 1e18, while the receiver has 10e18 available.  
- This means we need to take out 10 flash loans to deplete their funds.  

### Leveraging Multicall 

Fortunately, NaiveReceiverPool implements the following `multicall()` function:  

```solidity
function multicall(bytes[] calldata data) external virtual returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }
```
This allows us to **batch multiple calls into a single transaction**, making it possible to repeatedly trigger flash loans in one go.  

The main issue now is figuring out: _how to withdraw funds from the pool to the recovery account_. 
It’s likely that we need to leverage the forwarder to extract the drained funds.  

### Forwarder chapter

In `NaiveReceiverPool.sol`:
```solidity
    function _msgSender() internal view override returns (address) {
        if (msg.sender == trustedForwarder && msg.data.length >= 20) {
            return address(bytes20(msg.data[msg.data.length - 20:]));
        } else {
            return super._msgSender();
        }
    }
```

The point:
If the msg.sender is the trustedForwarder and the msg.data length is at least 20 bytes, it extracts the actual sender’s address from the last 20 bytes of msg.data.
So it seems we will be able to request as the deployer to withdraw.

In `BasicForwarder.sol`:








note pour moi:

le payload dans forwarder:
bytes memory payload = abi.encodePacked(request.data, request.from);
il met le from a la fin donc on peut juste mettre ce qu'on veut avant je pense et ca n'utilisera pas le from, donc a priori on peut bien impersonate?