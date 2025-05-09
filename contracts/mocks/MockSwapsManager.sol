// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract MockSwapsManager {
    uint256 public nextAmountOut;

    function setNextAmountOut(uint256 a) external {
        nextAmountOut = a;
    }

    function approveTokenWithPermit2(address, uint160, uint48) external {}

    function swap(PoolKey calldata, uint128, uint128, uint256, bool, address)
        external
        view
        returns (uint256 amountOut)
    {
        amountOut = nextAmountOut;
    }
}
