// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IMarketDataFetcher} from "../interfaces/IMarketDataFetcher.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MarketDataFetcher is IMarketDataFetcher, Ownable {
    uint256 public ETH_TOTAL_SUPPLY = 120_450_000;

    uint256 public BTC_TOTAL_SUPPLY = 21_000_000;

    mapping(address => address) tokenToUSDDataFeeds;

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Calculates the total market capitalization for an index and individual token market caps.
     * @param indexTokenAddresses Array of token addresses.
     * @return totalMarketCap The aggregated market capitalization.
     * @return individualMarketCaps Array of market capitalization values for each token.
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

    function setETHTotalSupply(uint256 _ethTotalSupply) external onlyOwner {
        ETH_TOTAL_SUPPLY = _ethTotalSupply;
    }

    function setBTCTotalSupply(uint256 _BTCTotalSupply) external onlyOwner {
        BTC_TOTAL_SUPPLY = _BTCTotalSupply;
    }

    function addDataFeed(address token, address dataFeed) external onlyOwner {
        tokenToUSDDataFeeds[token] = dataFeed;
    }

    function removeDataFeed(address token) external onlyOwner {
        delete tokenToUSDDataFeeds[token];
    }

    function getTokenMarketCap(address token) public view returns (uint256) {
        address tokenDataFeed = tokenToUSDDataFeeds[token];
        uint256 price = getTokenPrice(tokenDataFeed);
        uint256 totalSupply = _getTokenTotalSupply(token);
        return price * totalSupply;
    }

    function getTokenDataFeed(address token) public view returns (address) {
        return tokenToUSDDataFeeds[token];
    }

    /**
     * Returns the latest answer.
     */
    function getTokenPrice(address token) public view returns (uint256) {
        // retrieve the correct data feed
        address dataFeed = tokenToUSDDataFeeds[token];
        if (dataFeed == address(0)) {
            revert DataFeedDoesNotExist(token, true);
        }
        // prettier-ignore
        (
            /* uint80 roundId */
            ,
            int256 answer,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(dataFeed).latestRoundData();
        uint8 decimals = AggregatorV3Interface(dataFeed).decimals();
        return uint256(answer / int256(10 ** decimals));
    }

    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function _getTokenTotalSupply(address token) internal view returns (uint256) {
        if (_compareStrings(ERC20(token).symbol(), "WBTC")) {
            return BTC_TOTAL_SUPPLY;
        } else if (address(token) == address(0) || _compareStrings(ERC20(token).symbol(), "WETH")) {
            return ETH_TOTAL_SUPPLY;
        }
        return ERC20(token).totalSupply();
    }
}
