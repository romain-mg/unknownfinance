// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "./ERC20Encryption/ConfidentialERC20WithErrorsMintableBurnable.sol";

/// @notice This contract implements an encrypted ERC20-like token with confidential balances using Zama's FHE library.
/// @dev It supports typical ERC20 functionality such as transferring tokens, minting, and setting allowances,
/// @dev but uses encrypted data types.
contract IndexFundToken is SepoliaZamaFHEVMConfig, ConfidentialERC20WithErrorsMintableBurnable {
    /// @notice Constructor to initialize the token's name and symbol, and set up the owner
    /// @param name_ The name of the token
    /// @param symbol_ The symbol of the token
    constructor(
        string memory name_,
        string memory symbol_
    ) ConfidentialERC20WithErrorsMintableBurnable(name_, symbol_, msg.sender) {}
    function balanceOfAllow(address account) public returns (euint64) {
        euint64 balance = _balances[account];
        TFHE.allowTransient(balance, msg.sender);
        return balance;
    }
}
