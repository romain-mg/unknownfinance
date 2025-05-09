// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IConfidentialERC20Wrapped} from "@httpz-contracts/token/ERC20/IConfidentialERC20Wrapped.sol";
import "fhevm/gateway/GatewayCaller.sol";
import "fhevm/config/ZamaFHEVMConfig.sol";
import "fhevm/config/ZamaGatewayConfig.sol";
import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";
import {CustomConfidentialERC20WithErrors} from "./CustomConfidentialERC20WithErrors.sol";
import {CustomConfidentialERC20Wrapped} from "./CustomConfidentialERC20Wrapped.sol";
import {euint8, TFHE} from "fhevm/lib/TFHE.sol";
import {ConfidentialERC20Base} from "./ConfidentialERC20Base.sol";
import {ConfidentialERC20} from "@httpz-contracts/token/ERC20/ConfidentialERC20.sol";

/**
 * @title ConfidentialERC20Final
 * @notice A concrete contract combining wrapping/unwrapping functionality with encrypted error support.
 */
contract ConfidentialERC20WithErrorsWrapped is
    SepoliaZamaFHEVMConfig,
    SepoliaZamaGatewayConfig,
    CustomConfidentialERC20Wrapped,
    CustomConfidentialERC20WithErrors
{
    /**
     * @notice Initializes the contract with the ERC20 token address and max decryption delay.
     * @param erc20_ ERC20 token address to be wrapped.
     * @param maxDecryptionDelay_ Maximum decryption delay allowed.
     */
    constructor(address erc20_, uint256 maxDecryptionDelay_)
        CustomConfidentialERC20Wrapped(erc20_, maxDecryptionDelay_)
        CustomConfidentialERC20WithErrors()
        ConfidentialERC20Base(
            string(abi.encodePacked("Confidential ", IERC20Metadata(erc20_).name())),
            string(abi.encodePacked(IERC20Metadata(erc20_).symbol(), "c"))
        )
    {}

    function _transferNoEvent(address from, address to, euint64 amount, ebool isTransferable)
        internal
        virtual
        override(CustomConfidentialERC20Wrapped, ConfidentialERC20)
    {
        CustomConfidentialERC20Wrapped._transferNoEvent(from, to, amount, isTransferable);
    }

    function _updateAllowance(address owner, address spender, euint64 amount)
        internal
        virtual
        override(CustomConfidentialERC20WithErrors, ConfidentialERC20)
        returns (ebool)
    {
        return CustomConfidentialERC20WithErrors._updateAllowance(owner, spender, amount);
    }

    function transfer(address to, euint64 amount)
        public
        virtual
        override(CustomConfidentialERC20WithErrors, ConfidentialERC20)
        returns (bool)
    {
        return CustomConfidentialERC20WithErrors.transfer(to, amount);
    }

    function transferFrom(address from, address to, euint64 amount)
        public
        virtual
        override(CustomConfidentialERC20WithErrors, ConfidentialERC20)
        returns (bool)
    {
        return CustomConfidentialERC20WithErrors.transferFrom(from, to, amount);
    }

    function _transfer(address from, address to, euint64 amount, ebool isTransferable)
        internal
        override(CustomConfidentialERC20WithErrors, ConfidentialERC20)
    {
        CustomConfidentialERC20Wrapped._canTransferOrUnwrap(from);
        CustomConfidentialERC20WithErrors._transfer(from, to, amount, isTransferable);
    }

    function errorGetCounter() public view returns (uint256) {
        return _errorGetCounter();
    }
}
