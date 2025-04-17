// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapsManager {
    error InsufficientSwapOutput(address token, uint256 expectedAmount, uint256 actualAmount);

    error SwapOutputTransferFailed(address to, IERC20 token, uint256 amount);
}
