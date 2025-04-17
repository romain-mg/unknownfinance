// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import {ConfidentialERC20WithTransparentErrorsMintable} from "./ConfidentialERC20WithTransparentErrorsMintable.sol";

/**
 * @title   ConfidentialERC20WithErrorsMintable.
 * @notice  This contract inherits ConfidentialERC20WithErrors.
 * @dev     It allows an owner to mint tokens. Mint amounts are public.
 */
abstract contract ConfidentialERC20WithTransparentErrorsMintableBurnable is
    ConfidentialERC20WithTransparentErrorsMintable
{
    /**
     * @notice Emitted when `amount` tokens are minted to one account (`to`).
     */
    event Burn(address indexed to, uint64 amount);

    /**
     * @param name_     Name of the token.
     * @param symbol_   Symbol.
     * @param owner_    Owner address.
     */
    constructor(string memory name_, string memory symbol_, address owner_)
        ConfidentialERC20WithTransparentErrorsMintable(name_, symbol_, owner_)
    {}

    function burn(uint64 amount) public {
        _unsafeBurn(msg.sender, amount);
    }

    function _unsafeBurn(address account, uint64 amount) internal {
        _unsafeBurnNoEvent(account, amount);
        emit Transfer(account, address(0), _PLACEHOLDER);
    }

    /**
     * @dev It does not incorporate any overflow check. It must be implemented
     *      by the function calling it.
     */
    function _unsafeBurnNoEvent(address account, uint64 amount) internal {
        euint64 newBalanceAccount = TFHE.sub(_balances[account], amount);
        _balances[account] = newBalanceAccount;
        TFHE.allowThis(newBalanceAccount);
        TFHE.allow(newBalanceAccount, account);
    }
}
