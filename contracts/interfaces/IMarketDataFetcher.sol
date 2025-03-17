// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IMarketDataFetcher {
    function getIndexMarketCap(
        address[] calldata indexTokenAddresses,
        PoolKey[] calldata keys
    ) external view returns (uint256);

    function getTokenMarketCap(address token, PoolKey calldata key) external view returns (uint256);
}
