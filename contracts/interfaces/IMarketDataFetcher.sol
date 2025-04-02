// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

interface IMarketDataFetcher {
    error DataFeedDoesNotExist(address token, bool isAgainstUSD);

    function getIndexMarketCaps(address[] calldata indexTokenAddresses)
        external
        view
        returns (uint256 totalMarketCap, uint256[] memory individualMarketCaps);

    function getTokenMarketCap(address token) external view returns (uint256);

    function getTokenPrice(address token) external view returns (uint256);
}
