// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import {ConfidentialERC20WithErrors} from
    "@httpz-contracts/token/ERC20/extensions/ConfidentialERC20WithErrorsMintable.sol";
import {ConfidentialERC20} from "@httpz-contracts/token/ERC20/ConfidentialERC20.sol";
import {EncryptedErrors} from "@httpz-contracts/utils/EncryptedErrors.sol";
import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";
import {ConfidentialERC20Base} from "./ConfidentialERC20Base.sol";
import {TFHE} from "fhevm/lib/TFHE.sol";
/**
 * @title   ConfidentialERC20WithErrorsMintable.
 * @notice  This contract inherits ConfidentialERC20WithErrors.
 * @dev     It allows an owner to mint tokens. Mint amounts are public.
 */

enum ErrorCodes {
    NO_ERROR,
    UNSUFFICIENT_BALANCE,
    UNSUFFICIENT_APPROVAL
}

event Mint(address indexed to, uint64 amount);

abstract contract CustomConfidentialERC20WithErrors is
    ConfidentialERC20Base,
    SepoliaZamaFHEVMConfig,
    EncryptedErrors
{
    constructor() EncryptedErrors(uint8(type(ErrorCodes).max)) {}

    /**
     * @notice See {IConfidentialERC20-transfer}.
     */
    function transfer(address to, euint64 amount) public virtual override returns (bool) {
        _isSenderAllowedForAmount(amount);
        /// @dev Check whether the owner has enough tokens.
        ebool canTransfer = TFHE.asEbool(true);
        euint8 errorCode = _errorDefineIfNot(canTransfer, uint8(ErrorCodes.UNSUFFICIENT_BALANCE));
        _errorSave(errorCode);
        TFHE.allow(errorCode, msg.sender);
        TFHE.allow(errorCode, to);
        _transfer(msg.sender, to, amount, canTransfer);
        return true;
    }

    /**
     * @notice See {IConfidentialERC20-transferFrom}.
     */
    function transferFrom(address from, address to, euint64 amount) public virtual override returns (bool) {
        _isSenderAllowedForAmount(amount);
        address spender = msg.sender;
        ebool isTransferable = _updateAllowance(from, spender, amount);
        _transfer(from, to, amount, isTransferable);
        return true;
    }

    /**
     * @notice            Return the error for a transfer id.
     * @param transferId  Transfer id. It can be read from the `Transfer` event.
     * @return errorCode  Encrypted error code.
     */
    function getErrorCodeForTransferId(uint256 transferId) public virtual returns (euint8) {
        euint8 errorCode = _errorGetCodeEmitted(transferId);
        TFHE.allowTransient(errorCode, msg.sender);
        return errorCode;
    }

    function _transfer(address from, address to, euint64 amount, ebool isTransferable) internal virtual override {
        _transferNoEvent(from, to, amount, isTransferable);
        /// @dev It was incremented in _saveError.
        emit Transfer(from, to, _errorGetCounter() - 1);
    }

    function _updateAllowance(address owner, address spender, euint64 amount)
        internal
        virtual
        override
        returns (ebool isTransferable)
    {
        euint64 currentAllowance = _allowance(owner, spender);
        /// @dev It checks whether the allowance suffices.
        ebool allowedTransfer = TFHE.le(amount, currentAllowance);
        euint8 errorCode = _errorDefineIfNot(allowedTransfer, uint8(ErrorCodes.UNSUFFICIENT_APPROVAL));
        /// @dev It checks that the owner has enough tokens.
        ebool canTransfer = TFHE.le(amount, _balances[owner]);
        ebool isNotTransferableButIsApproved = TFHE.and(TFHE.not(canTransfer), allowedTransfer);
        errorCode = _errorChangeIf(
            isNotTransferableButIsApproved,
            /// @dev Should indeed check that spender is approved to not leak information.
            ///      on balance of `from` to unauthorized spender via calling reencryptTransferError afterwards.
            uint8(ErrorCodes.UNSUFFICIENT_BALANCE),
            errorCode
        );
        _errorSave(errorCode);
        TFHE.allow(errorCode, owner);
        TFHE.allow(errorCode, spender);
        isTransferable = TFHE.and(canTransfer, allowedTransfer);
        _approve(owner, spender, TFHE.select(isTransferable, TFHE.sub(currentAllowance, amount), currentAllowance));
    }
}
