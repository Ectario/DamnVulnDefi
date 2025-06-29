# Notes

## Overview

Goal: drain everything from the vault

```solidity
    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
```

Intersting vault setup:

```solidity
    function initialize(address admin, address proposer, address sweeper) external initializer {
        // Initialize inheritance chain
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        // Deploy timelock and transfer ownership to it
        transferOwnership(address(new ClimberTimelock(admin, proposer)));

        _setSweeper(sweeper);
        _updateLastWithdrawalTimestamp(block.timestamp);
    }
```

Ownership is transferred to `ClimberTimelock`.

Also, there’s a role that might be useful to drain every single kopek from the vault:

```solidity
// Allows trusted sweeper account to retrieve any tokens
function sweepFunds(address token) external onlySweeper {
    SafeTransferLib.safeTransfer(token, _sweeper, IERC20(token).balanceOf(address(this)));
}
```

But there’s a catch, you need to have the **sweeper role**.
*(Note: the challenge is called “Climber”... maybe I’m crazy, but it kinda feels like a hint toward privilege escalation? Or is it just an upgrade pun? I've no clue yet)*

Time to take a look at `ClimberTimelock.sol`.

And this part is **VERY interesting**:

```solidity
    /**
     * Anyone can execute what's been scheduled via `schedule`
     */
    function execute(address[] calldata targets, uint256[] calldata values, bytes[] calldata dataElements, bytes32 salt)
        external
        payable
    {
        if (targets.length <= MIN_TARGETS) {
            revert InvalidTargetsCount();
        }

        if (targets.length != values.length) {
            revert InvalidValuesCount();
        }

        if (targets.length != dataElements.length) {
            revert InvalidDataElementsCount();
        }

        bytes32 id = getOperationId(targets, values, dataElements, salt);

        for (uint8 i = 0; i < targets.length; ++i) {
            targets[i].functionCallWithValue(dataElements[i], values[i]);
        }

        if (getOperationState(id) != OperationState.ReadyForExecution) {
            revert NotReadyForExecution(id);
        }

        operations[id].executed = true;
    }
```

Wuuuuuut?

> **Anyone can execute what's been scheduled via `schedule`**

But the check for whether the operation was scheduled happens **AFTER** the call!!

```solidity
        bytes32 id = getOperationId(targets, values, dataElements, salt);

        for (uint8 i = 0; i < targets.length; ++i) {
            targets[i].functionCallWithValue(dataElements[i], values[i]);
        }

        if (getOperationState(id) != OperationState.ReadyForExecution) {
            revert NotReadyForExecution(id);
        }
```

So we can impersonate and forge operations, and do whatever we want **before** the security check?

Reading the logic, it seems anyone can execute, but ALSO provide arbitrary arguments??????
The other checks are purely structural, not restrictive.

**Annnnnnd** we get a free, fully controlled call **from** the `ClimberTimelock`.

That’s a win, since it’s its **own owner** (thanks to this line in the constructor:
`_grantRole(ADMIN_ROLE, address(this)); // self-administration`).

So we can just execute an undeclared operation with our crafted data and grant ourselves the sweeper role, and then just dump the vault.

To grant the role, in `AccessControl.sol` (inherited), there’s this function:

```solidity
    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(bytes32 role, address account) public virtual onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }
```

EDIT: Oups, there is no SWEEPER_ROLE in here, I forgot :x

Let’s just go for a more brutal approach and directly upgrade the vault’s implementation to our own, with a backdoored function that transfers everything to us.

This is possible because the following check (from the Vault implementation) is bypassed, as ownership was transferred to the `ClimberTimelock` during the vault's initialization:


```solidity
// By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
```

Btw, the upgradeAndCall to performs is:

```solidity
    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     *
     * @custom:oz-upgrades-unsafe-allow-reachable delegatecall
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data);
    }
```

## Lil' Problem Encountered

**Problem solved:**

* We need to schedule an operation, otherwise it will revert after the calls. ✅
  This is handled by using an `ExploitHelper`, called from within the same logic (inside `execute`), after granting it the `PROPOSER_ROLE` — thanks again to the self-administration policy of the timelock.

**Problem encountered:**

* The schedule must be set at least 1 hour *before* the operation...
  So, does that mean it can't be done atomically as I've tried? Or maybe it can?
  The issue comes from the delay, let's see if we can overwrite the delay storage slot by upgrading something or through another trick.

**Answer:**
That's easy, the timelock has a public onlyowner-like setter for the delay.
Let's just include a call to it in our atomic operation batch.