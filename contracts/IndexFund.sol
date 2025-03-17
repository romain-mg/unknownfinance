// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./marketData/MarketDataFetcher.sol";
import "./IndexFundToken.sol";
import ""

contract IndexFund {
    address[] indexTokens;

    IndexFundToken indexFundToken;

    MarketDataFetcher marketDataFetcher;



    address stablecoin;

    uint256 sharePrice;

    uint256 totalIndexMarketCap;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(address indexed user, uint256 indexed amount, uint256 indexed stablecoinIn);

    event SharesBurned(address indexed user, uint256 indexed amount);

    constructor(
        address[] memory _indexTokens,
        address _IndexFundToken,
        address _stablecoin,
        uint256 _initialSharePrice
    ) {
        indexTokens = _indexTokens;
        IndexFundToken = _IndexFundToken;
        stablecoin = _stablecoin;
        sharePrice = _initialSharePrice;
    }

    function mintShares(uint256 amount) public {}

    function burnShares(uint256 amount) public {}

    function getIndexTokens() public view returns (address[] memory) {
        return indexTokens;
    }

    function getIndexFundToken() public view returns (address) {
        return IndexFundToken;
    }

    function getStablecoin() public view returns (address) {
        return stablecoin;
    }
}
