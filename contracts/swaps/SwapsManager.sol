// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { UniversalRouter } from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import { Commands } from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import { IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey, Currency } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { ISwapsManager } from "../interfaces/ISwapsManager.sol";
import { equals, CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * @title SwapsManager
 * @notice Manages token swaps using Uniswap V4 and Universal Router
 * @dev This contract handles the execution of swaps between tokens and stablecoins,
 * including permit2 approvals and swap execution through Uniswap V4 pools.
 * It is upgradeable and ownable for administrative control.
 */
contract SwapsManager is Initializable, UUPSUpgradeable, OwnableUpgradeable, ISwapsManager {
    UniversalRouter public router;

    IPermit2 public permit2;

    /**
     * @notice Approves a token for spending by the permit2 contract
     * @param token The address of the token to approve
     * @param amount The amount to approve
     * @param expiration The expiration timestamp for the approval
     */
    function approveTokenWithPermit2(address token, uint160 amount, uint48 expiration) external {
        IERC20(token).approve(address(permit2), type(uint256).max);
        permit2.approve(token, address(router), amount, expiration);
    }

    /**
     * @notice Executes a swap between tokens using Uniswap V4
     * @param key The pool key containing the token pair information
     * @param amountIn The amount of input token to swap
     * @param minAmountOut The minimum amount of output token to receive
     * @param deadline The deadline for the swap execution
     * @param stablecoinForToken Whether the swap is from stablecoin to token
     * @param stablecoinAddress The address of the stablecoin
     * @return amountOut The amount of output token received
     */
    function swap(
        PoolKey calldata key,
        uint128 amountIn,
        uint128 minAmountOut,
        uint256 deadline,
        bool stablecoinForToken,
        address stablecoinAddress
    ) public payable returns (uint256 amountOut) {
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        bool zeroForOne = stablecoinForToken == (Currency.unwrap(key.currency0) == stablecoinAddress);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(key.currency0, amountIn);
        params[2] = abi.encode(key.currency1, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        router.execute(commands, inputs, deadline);

        // Verify and return the output amount to the caller
        bool success;
        if (zeroForOne) {
            amountOut = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(this));
            success = IERC20(Currency.unwrap(key.currency1)).transfer(msg.sender, amountOut);
        } else if (equals(key.currency0, CurrencyLibrary.ADDRESS_ZERO)) {
            amountOut = address(this).balance;
            (success, ) = msg.sender.call{ value: amountOut }("");
        } else {
            amountOut = IERC20(Currency.unwrap(key.currency0)).balanceOf(address(this));
            success = IERC20(Currency.unwrap(key.currency0)).transfer(msg.sender, amountOut);
        }

        if (amountOut < minAmountOut) {
            revert InsufficientSwapOutput(Currency.unwrap(key.currency1), amountOut, minAmountOut);
        }
        if (!success) revert SwapOutputTransferFailed(msg.sender, IERC20(Currency.unwrap(key.currency1)), amountOut);
        return amountOut;
    }

    /**
     * @notice Initializes the contract with required addresses
     * @param _router The address of the Universal Router
     * @param _permit2 The address of the Permit2 contract
     */
    function initialize(address _router, address _permit2) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        router = UniversalRouter(payable(_router));
        permit2 = IPermit2(_permit2);
    }

    /**
     * @notice Authorizes an upgrade to a new implementation
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
