// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ConfidentialERC20} from "@httpz-contracts/token/ERC20/ConfidentialERC20.sol";
import {TFHE, euint64} from "fhevm/lib/TFHE.sol";

/**
 * @notice Centralizes initialization of ConfidentialERC20 for diamond inheritance
 */
abstract contract ConfidentialERC20Base is ConfidentialERC20 {
    constructor(string memory name_, string memory symbol_) ConfidentialERC20(name_, symbol_) {}
}
