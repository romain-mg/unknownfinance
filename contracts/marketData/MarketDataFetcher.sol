// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IMarketDataFetcher} from "../interfaces/IMarketDataFetcher.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MarketDataFetcher
 * @notice Fetches and manages market data for tokens
 * @dev This contract integrates with Chainlink price feeds to provide real-time token prices
 * and calculates market capitalizations. It maintains a mapping of tokens to their price feeds
 * and handles special cases for native ETH and wrapped BTC.
 */
contract MarketDataFetcher is IMarketDataFetcher, Ownable {
    uint256 public ETH_TOTAL_SUPPLY = 120_450_000;

    uint256 public BTC_TOTAL_SUPPLY = 21_000_000;

    uint256 private constant USDC_DECIMALS = 1e6;

    mapping(address => address) tokenToUSDDataFeeds;

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Calculates the total market capitalization for an index and individual token market caps
     * @param indexTokenAddresses Array of token addresses in the index
     * @return totalMarketCap The aggregated market capitalization of all tokens
     * @return individualMarketCaps Array of market capitalization values for each token
     */
    function getIndexMarketCaps(address[] calldata indexTokenAddresses)
        external
        view
        returns (uint256 totalMarketCap, uint256[] memory individualMarketCaps)
    {
        totalMarketCap = 0;
        individualMarketCaps = new uint256[](indexTokenAddresses.length);
        for (uint256 i = 0; i < indexTokenAddresses.length; i++) {
            totalMarketCap += getTokenMarketCap(indexTokenAddresses[i]);
            individualMarketCaps[i] = getTokenMarketCap(indexTokenAddresses[i]);
        }
        return (totalMarketCap, individualMarketCaps);
    }

    /**
     * @notice Updates the total supply of ETH used for market cap calculations
     * @param _ethTotalSupply The new total supply value
     */
    function setETHTotalSupply(uint256 _ethTotalSupply) external onlyOwner {
        ETH_TOTAL_SUPPLY = _ethTotalSupply;
    }

    /**
     * @notice Updates the total supply of BTC used for market cap calculations
     * @param _BTCTotalSupply The new total supply value
     */
    function setBTCTotalSupply(uint256 _BTCTotalSupply) external onlyOwner {
        BTC_TOTAL_SUPPLY = _BTCTotalSupply;
    }

    /**
     * @notice Adds a new price feed for a token
     * @param token The address of the token
     * @param dataFeed The address of the Chainlink price feed
     */
    function addDataFeed(address token, address dataFeed) external onlyOwner {
        tokenToUSDDataFeeds[token] = dataFeed;
    }

    /**
     * @notice Removes a price feed for a token
     * @param token The address of the token whose feed should be removed
     */
    function removeDataFeed(address token) external onlyOwner {
        delete tokenToUSDDataFeeds[token];
    }

    /**
     * @notice Calculates the market capitalization for a specific token
     * @param token The address of the token
     * @return The market capitalization in USD (price * total supply)
     */
    function getTokenMarketCap(address token) public view returns (uint256) {
        address tokenDataFeed = tokenToUSDDataFeeds[token];
        uint256 price = getTokenPrice(tokenDataFeed);
        uint256 totalSupply = _getTokenTotalSupply(token);
        return price * totalSupply;
    }

    /**
     * @notice Gets the price feed address for a token
     * @param token The address of the token
     * @return The address of the token's price feed
     */
    function getTokenDataFeed(address token) public view returns (address) {
        return tokenToUSDDataFeeds[token];
    }

    /**
     * @notice Gets the latest price for a token from its price feed
     * @param token The address of the token's price feed
     * @return The token price in USD with 6 decimals
     * @dev Reverts if the price feed doesn't exist
     */
    function getTokenPrice(address token) public view returns (uint256) {
        // retrieve the correct data feed
        address dataFeed = tokenToUSDDataFeeds[token];
        if (dataFeed == address(0)) {
            revert DataFeedDoesNotExist(token, true);
        }
        (, int256 answer,,,) = AggregatorV3Interface(dataFeed).latestRoundData();
        uint8 feedDecimals = AggregatorV3Interface(dataFeed).decimals();
        // price6 = (rawAnswer × 1e6) / feedDecimals
        return (uint256(answer) * USDC_DECIMALS) / (10 ** feedDecimals);
    }

    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    /**
     * @notice Gets the total supply for a token, handling special cases for ETH and BTC
     * @param token The address of the token
     * @return The total supply of the token
     */
    function _getTokenTotalSupply(address token) internal view returns (uint256) {
        if (_compareStrings(ERC20(token).symbol(), "WBTC")) {
            return BTC_TOTAL_SUPPLY;
        } else if (address(token) == address(0) || _compareStrings(ERC20(token).symbol(), "WETH")) {
            return ETH_TOTAL_SUPPLY;
        }
        return ERC20(token).totalSupply();
    }
}
