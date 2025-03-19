// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IERC20 } from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

interface ISwapsManager {
    error SwapOutputTransferFailed(address to, IERC20 token, uint256 amount);
    function swapExactInputSingle(
        PoolKey calldata key,
        uint128 amountIn,
        uint128 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountOut);
}
