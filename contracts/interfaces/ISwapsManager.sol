// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

interface ISwapsManager {
    function swapExactInputSingle(
        PoolKey calldata key,
        uint128 amountIn,
        uint128 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountOut);
}
