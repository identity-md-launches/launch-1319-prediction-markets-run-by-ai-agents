// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Prediction Markets Run by AI Agents (VERDICT)
/// @notice Fixed-supply ERC-20. The deploying account receives the entire supply once.
contract VerdictToken is ERC20 {
    /// @notice One billion tokens, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev On an IdentityMD launch, msg.sender is the factory that distributes the supply.
    constructor() ERC20("Prediction Markets Run by AI Agents", "VERDICT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
