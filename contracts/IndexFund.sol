// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IIndexFund } from "./interfaces/IIndexFund.sol";
import { IndexFundToken } from "./IndexFundToken.sol";
import { IERC20 } from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

contract IndexFund is IIndexFund {
    address[] indexTokens;
    PoolKey[] poolKeys;

    IERC20 indexFundToken;

    address marketDataFetcherProxy;

    address swapsManagerProxy;

    IERC20 stablecoin;

    uint256 sharePrice;

    uint256 totalIndexMarketCap;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(address indexed user, uint256 indexed amount, uint256 indexed stablecoinIn);

    event SharesBurned(address indexed user, uint256 indexed amount);

    constructor(
        address[] memory _indexTokens,
        address _stablecoin,
        address _indexFundToken,
        address _marketDataFetcherProxy,
        address _swapsManagerProxy,
        uint256 _initialSharePrice
    ) {
        indexTokens = _indexTokens;
        stablecoin = IERC20(_stablecoin);
        indexFundToken = IERC20(_indexFundToken);
        marketDataFetcherProxy = _marketDataFetcherProxy;
        swapsManagerProxy = _swapsManagerProxy;
        sharePrice = _initialSharePrice;
    }

    function mintShares(uint256 amount) public {}

    function burnShares(uint256 amount) public {}

    function getIndexTokens() public view returns (address[] memory) {
        return indexTokens;
    }

    function getIndexFundToken() public view returns (IERC20) {
        return indexFundToken;
    }

    function getStablecoin() public view returns (IERC20) {
        return stablecoin;
    }

    function getPoolKeysFromIndexTokens() public view returns (PoolKey[] memory) {}
}
