// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "./swaps/SwapsManager.sol";
import "./IndexFundToken.sol";
import "./marketData/MarketDataFetcher.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./interfaces/IIndexFund.sol";
import "./interfaces/ISwapsManager.sol";
import "./interfaces/IMarketDataFetcher.sol";

contract IndexFund is IIndexFund {
    address[] indexTokens;

    IERC20 indexFundToken;

    IMarketDataFetcher marketDataFetcher;

    ISwapsManager swapsManager;

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
        address _marketDataFetcher,
        address _swapsManager,
        uint256 _initialSharePrice
    ) {
        indexTokens = _indexTokens;
        stablecoin = IERC20(_stablecoin);
        indexFundToken = IERC20(_indexFundToken);
        marketDataFetcher = IMarketDataFetcher(_marketDataFetcher);
        swapsManager = ISwapsManager(_swapsManager);
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
}
