// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import "fhevm/lib/TFHE.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "./ERC20Encryption/ConfidentialERC20WithErrorsMintableBurnable.sol";

/**
 * @title IndexFundToken
 * @notice Implements a confidential ERC20 token for index funds using Zama's FHE (Fully Homomorphic Encryption)
 * @dev This contract extends ConfidentialERC20WithErrorsMintableBurnable to provide encrypted token functionality
 * for index funds. It enables confidential transfers, minting, and burning of tokens while maintaining
 * privacy of balances and transactions.
 *
 * Key features:
 * - Encrypted balance tracking using FHE
 * - Confidential transfers between accounts
 * - Minting and burning capabilities
 * - Allowance management with encrypted values
 * - Transient balance access for authorized parties
 */
contract IndexFundToken is SepoliaZamaFHEVMConfig, ConfidentialERC20WithErrorsMintableBurnable {
    constructor(string memory name_, string memory symbol_)
        ConfidentialERC20WithErrorsMintableBurnable(name_, symbol_, msg.sender)
    {}

    /**
     * @notice Allows temporary access to an account's encrypted balance
     * @param account The address of the account whose balance to access
     * @return The encrypted balance of the account
     * @dev This function enables temporary access to encrypted balances for authorized parties
     * while maintaining confidentiality. The balance is only accessible to the caller.
     */
    function balanceOfAllow(address account) public returns (euint64) {
        euint64 balance = _balances[account];
        TFHE.allowTransient(balance, msg.sender);
        return balance;
    }
}
