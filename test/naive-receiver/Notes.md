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

_Note: We obviously can't directly call the function ourselves while arbitrarily adding fees, because of the assembly check: `if iszero(eq(sload(pool.slot), caller()))`. This essentially verifies whether the caller is the pool contract and reverts if it's not. In other words, only the pool itself can initiate this call, preventing us from manually triggering it with modified parameters... It would have been too easy x(_

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
This allows us to batch multiple calls into a single transaction, making it possible to repeatedly trigger flash loans in one go.  

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
So it seems we will be able to request a the deployer to withdraw.

**EDIT: wtf did i think, we can't manipulate the last 20 bytes since it's the forwarder who append it, confusion between "first" and "last" item...**

In `BasicForwarder.sol`:

```solidity
    function execute(Request calldata request, bytes calldata signature) public payable returns (bool success) {
        _checkRequest(request, signature);   //                                                 <------ check the request and the signature for it

        nonces[request.from]++;//                                                               <------ used for the test dealing with the fact that we must do everything in less than 2 txs

        uint256 gasLeft;
        uint256 value = request.value; // in wei
        address target = request.target;
        bytes memory payload = abi.encodePacked(request.data, request.from);//                  <------ here we will be able to not use the true packed request.from (cf. the _msgSender() function describe above, EDIT: epic fail, confusion between "first" and "last" item xD )
        uint256 forwardGas = request.gas;
        assembly {
            success := call(forwardGas, target, value, add(payload, 0x20), mload(payload), 0, 0) // do the call
            gasLeft := gas()
        }

        if (gasLeft < request.gas / 63) {
            assembly {
                invalid()
            }
        }
    }
```

To validate the `_checkRequest`, we need to ensure that the Request's from field matches a valid signature. The verification relies on [EIP-712](https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct) structured data signing, so we must manually reconstruct the expected hash since `_hashTypedData()` in EIP712 is internal and inaccessible.

To achieve this, we use key elements available to us:  
- `getDataHash(Request)` to retrieve the structured Request hash.  
- `domainSeparator` for constructing the final hash.  
- `_domainNameAndVersion` (known despite being internal).  
- `getRequestTypeHash()` to format the request properly.  

By combining these, we can rebuild the EIP-712 message, concatenate it with the `domainSeparator`, and sign it using a private key to generate a valid ECDSA signature. 

So here the EIP712 hash & signing logic in Foundry:

```solidity
bytes32 digest = _hashTypedData(getDataHash(request));    //                 <---------- using our reconstructed EIP712 _hashTypedData function
(uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
bytes memory signature = abi.encodePacked(r, s, v);
```

```solidity
    function _hashTypedData(bytes32 structHash, bytes32 domainSeparator) internal view virtual returns (bytes32 digest) {
        digest = domainSeparator;
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the digest.
            mstore(0x00, 0x1901000000000000) // Store "\x19\x01".
            mstore(0x1a, digest) // Store the domain separator.
            mstore(0x3a, structHash) // Store the struct hash.
            digest := keccak256(0x18, 0x42)
            // Restore the part of the free memory slot that was overwritten.
            mstore(0x3a, 0)
        }
    }
```