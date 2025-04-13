// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import {ConfidentialERC20WithErrorsMintable} from "./ConfidentialERC20WithErrorsMintable.sol";

/**
 * @title   ConfidentialERC20WithErrorsMintable.
 * @notice  This contract inherits ConfidentialERC20WithErrors.
 * @dev     It allows an owner to mint tokens. Mint amounts are public.
 */
abstract contract ConfidentialERC20WithErrorsMintableBurnable is ConfidentialERC20WithErrorsMintable {
    /**
     * @notice Emitted when `amount` tokens are minted to one account (`to`).
     */
    event Burn(address indexed to, uint256 amount);

    /**
     * @param name_     Name of the token.
     * @param symbol_   Symbol.
     * @param owner_    Owner address.
     */
    constructor(string memory name_, string memory symbol_, address owner_)
        ConfidentialERC20WithErrorsMintable(name_, symbol_, owner_)
    {}

    function burn(uint256 amount) public {
        _unsafeBurn(msg.sender, amount);
    }

    function _unsafeBurn(address account, uint256 amount) internal {
        _unsafeBurnNoEvent(account, amount);
        emit Transfer(account, address(0), _PLACEHOLDER);
    }

    /**
     * @dev It does not incorporate any overflow check. It must be implemented
     *      by the function calling it.
     */
    function _unsafeBurnNoEvent(address account, uint256 amount) internal {
        euint256 newBalanceAccount = TFHE.sub(_balances[account], amount);
        _balances[account] = newBalanceAccount;
        TFHE.allowThis(newBalanceAccount);
        TFHE.allow(newBalanceAccount, account);
    }
}
