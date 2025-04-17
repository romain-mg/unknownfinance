// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import "@httpz-contracts/token/ERC20/ConfidentialERC20.sol";
import {TFHE, euint8, euint64} from "fhevm/lib/TFHE.sol";
import "fhevm/gateway/GatewayCaller.sol";
import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";
import {SepoliaZamaGatewayConfig} from "fhevm/config/ZamaGatewayConfig.sol";

/**
 * @title   ConfidentialERC20WithErrors.
 * @notice  This contract implements an encrypted ERC20-like token with confidential balances using
 *          Zama's FHE (Fully Homomorphic Encryption) library.
 * @dev     It supports standard ERC20 functions such as transferring tokens, minting,
 *          and setting allowances, but uses encrypted data types.
 *          The total supply is not encrypted.
 *          It also supports error handling for encrypted errors.
 */
abstract contract ConfidentialERC20WithTransparentErrors is
    ConfidentialERC20,
    SepoliaZamaFHEVMConfig,
    SepoliaZamaGatewayConfig,
    GatewayCaller
{
    /**
     * @notice Error codes allow tracking (in the storage) whether a transfer worked.
     * @dev    NO_ERROR: the transfer worked as expected.
     *         UNSUFFICIENT_BALANCE: the transfer failed because the
     *         from balances were strictly inferior to the amount to transfer.
     *         UNSUFFICIENT_APPROVAL: the transfer failed because the sender allowance
     *         was strictly lower than the amount to transfer.
     */
    enum ErrorCodes {
        NO_ERROR,
        UNSUFFICIENT_BALANCE,
        UNSUFFICIENT_APPROVAL
    }

    mapping(uint256 errorIndex => uint8 errorCode) private _errorCodesEmitted;

    uint256 private _errorCounter;

    /**
     * @param name_     Name of the token.
     * @param symbol_   Symbol.
     */
    constructor(string memory name_, string memory symbol_) ConfidentialERC20(name_, symbol_) {}

    /**
     * @notice See {IConfidentialERC20-transfer}.
     */
    function transfer(address to, euint64 amount) public override returns (bool) {
        _isSenderAllowedForAmount(amount);
        /// @dev Check whether the owner has enough tokens.
        ebool canTransfer = TFHE.le(amount, _balances[msg.sender]);
        euint8 errorCode = TFHE.select(
            canTransfer, _errorCodeToEuint8(ErrorCodes.NO_ERROR), _errorCodeToEuint8(ErrorCodes.UNSUFFICIENT_BALANCE)
        );
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(errorCode);
        Gateway.requestDecryption(cts, this.transferCallback.selector, 0, block.timestamp + 100, false);
        _transfer(msg.sender, to, amount, canTransfer);
        return true;
    }

    /**
     * @notice See {IConfidentialERC20-transferFrom}.
     */
    function transferFrom(address from, address to, euint64 amount) public override returns (bool) {
        _isSenderAllowedForAmount(amount);
        address spender = msg.sender;
        ebool isTransferable = _updateAllowance(from, spender, amount);
        _transfer(from, to, amount, isTransferable);
        return true;
    }

    function transferCallback(uint256, /*requestID*/ uint8 decryptedErrorCode) public onlyGateway {
        _saveError(decryptedErrorCode);
    }

    /**
     * @notice            Return the error for a transfer id.
     * @param transferId  Transfer id. It can be read from the `Transfer` event.
     * @return errorCode  Error code.
     */
    function getErrorCodeForTransferId(uint256 transferId) public view returns (uint8 errorCode) {
        errorCode = _errorCodesEmitted[transferId];
    }

    function errorGetCounter() public view returns (uint256 countErrors) {
        return _errorCounter;
    }

    function _transfer(address from, address to, euint64 amount, ebool isTransferable) internal override {
        _transferNoEvent(from, to, amount, isTransferable);
        /// @dev It was incremented in _saveError.
        emit Transfer(from, to, errorGetCounter() - 1);
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
        euint8 errorCode = TFHE.select(
            allowedTransfer,
            _errorCodeToEuint8(ErrorCodes.NO_ERROR),
            _errorCodeToEuint8(ErrorCodes.UNSUFFICIENT_APPROVAL)
        );
        /// @dev It checks that the owner has enough tokens.
        ebool canTransfer = TFHE.le(amount, _balances[owner]);
        ebool isNotTransferableButIsApproved = TFHE.and(TFHE.not(canTransfer), allowedTransfer);
        errorCode = TFHE.select(
            isNotTransferableButIsApproved,
            /// @dev Should indeed check that spender is approved to not leak information.
            ///      on balance of `from` to unauthorized spender via calling reencryptTransferError afterwards.
            _errorCodeToEuint8(ErrorCodes.UNSUFFICIENT_BALANCE),
            _errorCodeToEuint8(ErrorCodes.NO_ERROR)
        );
        /// @dev Decrypts the error code and saves it
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(errorCode);
        Gateway.requestDecryption(cts, this.transferCallback.selector, 0, block.timestamp + 100, false);

        TFHE.allow(errorCode, owner);
        TFHE.allow(errorCode, spender);
        isTransferable = TFHE.and(canTransfer, allowedTransfer);
        _approve(owner, spender, TFHE.select(isTransferable, TFHE.sub(currentAllowance, amount), currentAllowance));
    }

    function _saveError(uint8 errorCode) internal returns (uint256 errorId) {
        errorId = _errorCounter;
        _errorCounter++;
        _errorCodesEmitted[errorId] = errorCode;
    }

    function _errorCodeToEuint8(ErrorCodes errorCode) internal returns (euint8 errorCodeAsEuint8) {
        errorCodeAsEuint8 = TFHE.asEuint8(uint8(errorCode));
    }
}
