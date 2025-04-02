// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapsManager {
    error InsufficientSwapOutput(address token, uint256 expectedAmount, uint256 actualAmount);

    error SwapOutputTransferFailed(address to, IERC20 token, uint256 amount);

    function swap(
        PoolKey calldata key,
        uint128 amountIn,
        uint128 minAmountOut,
        uint256 deadline,
        bool stablecoinForToken,
        address stablecoinAddress
    ) external returns (uint256 amountOut);

    function approveTokenWithPermit2(address token, uint160 amount, uint48 expiration) external;
}
