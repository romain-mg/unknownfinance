// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IMarketDataFetcher {
    function getIndexMarketCaps(address[] calldata indexTokenAddresses, PoolKey[] calldata keys)
        external
        view
        returns (uint256 totalMarketCap, uint256[] memory marketCaps);

    function getTokenMarketCap(address token, PoolKey calldata key) external view returns (uint256);

    function getTokenPrice(address token, PoolKey calldata key) external view returns (uint256);
}
