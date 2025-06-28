# Notes

Win conditions check:

```solidity
    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            assertTrue(wallet != address(0), "User didn't register a wallet");

            // User is no longer registered as a beneficiary
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }

        // Recovery account must own all tokens
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
```

- the player must complete the challenge in a single transaction, ensure each user registers a wallet, and remove them as beneficiaries _(note: it does it automatically via the callback in `WalletRegistry.sol` so we probably need to use it)_
- all distributed tokens must be recovered and held by the designated recovery address to meet the success criteria

> Note: Interesting that every user doesn't have its wallet created during the chall setup..

Let's see what kind of function we got..

```sh
ectario@pwnMachine:~/DamnVulnDefi(master⚡) » cast interface lib/safe-smart-account/contracts/proxies/SafeProxyFactory.sol 
```
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface SafeProxyFactory {
    event ProxyCreation(address indexed proxy, address singleton);

    function createChainSpecificProxyWithNonce(address _singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
    function createProxyWithCallback(address _singleton, bytes memory initializer, uint256 saltNonce, address callback)
        external
        returns (address proxy);
    function createProxyWithNonce(address _singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
    function getChainId() external view returns (uint256);
    function proxyCreationCode() external pure returns (bytes memory);
}


```sh
ectario@pwnMachine:~/DamnVulnDefi(master⚡) » cast interface lib/safe-smart-account/contracts/Safe.sol 
```
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library Enum {
    type Operation is uint8;
}

interface Safe {
    ... SNIP: Event / Errors / getters ...
    function addOwnerWithThreshold(address owner, uint256 _threshold) external;
    function approveHash(bytes32 hashToApprove) external;
    function changeThreshold(uint256 _threshold) external;
    function disableModule(address prevModule, address module) external;
    function enableModule(address module) external;
    function execTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
    function execTransactionFromModule(address to, uint256 value, bytes memory data, Enum.Operation operation)
        external
        returns (bool success);
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, Enum.Operation operation)
        external
        returns (bool success, bytes memory returnData);
    function removeOwner(address prevOwner, address owner, uint256 _threshold) external;
    function setFallbackHandler(address handler) external;
    function setGuard(address guard) external;
    function setup(
        address[] memory _owners,
        uint256 _threshold,
        address to,
        bytes memory data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
    function signedMessages(bytes32) external view returns (uint256);
    function simulateAndRevert(address targetContract, bytes memory calldataPayload) external;
    function swapOwner(address prevOwner, address oldOwner, address newOwner) external;
}

```

Interesting function is `setup` (and maybe `swapOwner` idk yet?)

In `OwnerManager.sol`:

```solidity
    /**
     * @notice Replaces the owner `oldOwner` in the Safe with `newOwner`.
     * @dev This can only be done via a Safe transaction.
     * @param prevOwner Owner that pointed to the owner to be replaced in the linked list
     * @param oldOwner Owner address to be replaced.
     * @param newOwner New owner address.
     */
    function swapOwner(address prevOwner, address oldOwner, address newOwner) public authorized {
        // Owner address cannot be null, the sentinel or the Safe itself.
        require(newOwner != address(0) && newOwner != SENTINEL_OWNERS && newOwner != address(this), "GS203");
        // No duplicate owners allowed.
        require(owners[newOwner] == address(0), "GS204");
        // Validate oldOwner address and check that it corresponds to owner index.
        require(oldOwner != address(0) && oldOwner != SENTINEL_OWNERS, "GS203");
        require(owners[prevOwner] == oldOwner, "GS205");
        owners[newOwner] = owners[oldOwner];
        owners[prevOwner] = newOwner;
        owners[oldOwner] = address(0);
        emit RemovedOwner(oldOwner);
```

modifier authorized declared in `SelfAuthorized.sol`:

```solidity
/**
 * @title SelfAuthorized - Authorizes current contract to perform actions to itself.
 * @author Richard Meissner - @rmeissner
 */
abstract contract SelfAuthorized {
    function requireSelfCall() private view {
        require(msg.sender == address(this), "GS031");
    }

    modifier authorized() {
        // Modifiers are copied around during compilation. This is a function call as it minimized the bytecode size
        requireSelfCall();
        _;
    }
}
```

Setup function from `Safe.sol`:

```solidity
    /**
     * @notice Sets an initial storage of the Safe contract.
     * @dev This method can only be called once.
     *      If a proxy was created without setting up, anyone can call setup and claim the proxy.
     * @param _owners List of Safe owners.
     * @param _threshold Number of required confirmations for a Safe transaction.
     * @param to Contract address for optional delegate call.
     * @param data Data payload for optional delegate call.
     * @param fallbackHandler Handler for fallback calls to this contract
     * @param paymentToken Token that should be used for the payment (0 is ETH)
     * @param payment Value that should be paid
     * @param paymentReceiver Address that should receive the payment (or 0 if tx.origin)
     */
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external {
        // setupOwners checks if the Threshold is already set, therefore preventing that this method is called twice
        setupOwners(_owners, _threshold);
        if (fallbackHandler != address(0)) internalSetFallbackHandler(fallbackHandler);
        // As setupOwners can only be called if the contract has not been initialized we don't need a check for setupModules
        setupModules(to, data);

        if (payment > 0) {
            // To avoid running into issues with EIP-170 we reuse the handlePayment function (to avoid adjusting code of that has been verified we do not adjust the method itself)
            // baseGas = 0, gasPrice = 1 and gas = payment => amount = (payment + 0) * 1 = payment
            handlePayment(payment, 0, 1, paymentToken, paymentReceiver);
        }
        emit SafeSetup(msg.sender, _owners, _threshold, to, fallbackHandler);
    }
```

wtf? 

    * @dev This method can only be called once.
    *      If a proxy was created without setting up, anyone can call setup and claim the proxy.

AND

    // As setupOwners can only be called if the contract has not been initialized we don't need a check for setupModules

Let's see what kind of things it can do. 
We might be able to create new proxies on behalf of other users (since they still haven't created their own wallet _-> first note I've written_) and by using this setup method, we could pull off some funky stuff. But let's dig a bit deeper to see what really is this `setupOwners`:

In `ModuleManager.sol`:
```solidity
    /**
     * @notice Setup function sets the initial storage of the contract.
     *         Optionally executes a delegate call to another contract to setup the modules.
     * @param to Optional destination address of call to execute.
     * @param data Optional data of call to execute.
     */
    function setupModules(address to, bytes memory data) internal {
        require(modules[SENTINEL_MODULES] == address(0), "GS100");
        modules[SENTINEL_MODULES] = SENTINEL_MODULES;
        if (to != address(0)) {
            require(isContract(to), "GS002");
            // Setup has to complete successfully or transaction fails.
            require(execute(to, 0, data, Enum.Operation.DelegateCall, type(uint256).max), "GS000");
        }
    }
```

In `Executor.sol`:

```solidity
// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;
import "../common/Enum.sol";

/**
 * @title Executor - A contract that can execute transactions
 * @author Richard Meissner - @rmeissner
 */
abstract contract Executor {
    /**
     * @notice Executes either a delegatecall or a call with provided parameters.
     * @dev This method doesn't perform any sanity check of the transaction, such as:
     *      - if the contract at `to` address has code or not
     *      It is the responsibility of the caller to perform such checks.
     * @param to Destination address.
     * @param value Ether value.
     * @param data Data payload.
     * @param operation Operation type.
     * @return success boolean flag indicating if the call succeeded.
     */
    function execute(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 txGas
    ) internal returns (bool success) {
        if (operation == Enum.Operation.DelegateCall) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0)
            }
        } else {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
            }
        }
    }
}
```

Crazy free delegate call?

So, since we want to gather all the bounties we will need the callback function, and as we saw `createProxyWithCallback` could be used from the proxy factory, so the chain seems to be:

    SafeProxyFactory::createProxyWithCallback -> our new proxy fallback -> Safe::setup -> OurSploit::approveBackdoor -> DamnValuableToken::approve our_exploit
    
    and then
    
    -> DamnValuableToken::transferFrom (our_new_proxy, recovery_account)

## Useful Docs

- https://docs.safe.global/advanced/smart-account-overview
- https://ethereum.stackexchange.com/questions/165874/setupmodulesto-data-help
- https://docs.safe.global/reference-smart-account/setup/setup
- https://blog.openzeppelin.com/backdooring-gnosis-safe-multisig-wallets
- https://gist.github.com/tinchoabbate/4b8be18615c4f4a4049280c014327652