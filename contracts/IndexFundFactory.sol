// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import {IndexFund} from "./IndexFund.sol";
import {IIndexFundFactory} from "./interfaces/IIndexFundFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolKey, Currency} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IndexFundToken} from "./IndexFundToken.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IIndexFund} from "./interfaces/IIndexFund.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract IndexFundFactory is IIndexFundFactory, Ownable {
    using CurrencyLibrary for Currency;

    mapping(bytes32 => PoolKey) public tokenStablecoinPairToPoolKey;

    mapping(bytes32 => IIndexFund) public indexTokensAndStablecoinToIndexFund;

    address public swapsManagerProxy;

    uint96 indexFundsCount;

    address public marketDataFetcherProxy;

    uint256 defaultSharePrice;

    uint256 public feeDivisor;

    constructor(
        address _swapsManagerProxy,
        address _markerDataFetcherProxy,
        uint256 _defaultSharePrice,
        uint256 _feeDivisor
    ) Ownable(msg.sender) {
        swapsManagerProxy = _swapsManagerProxy;
        marketDataFetcherProxy = _markerDataFetcherProxy;
        defaultSharePrice = _defaultSharePrice;
        feeDivisor = _feeDivisor;
    }
    /**
     * @notice Create a new index fund
     * @dev The function first checks that a pool is referenced in the factory's pool map for each token-stablecoin pair
     * @param indexTokens The tokens that make up the index fund
     * @param stablecoin The stablecoin that the index fund is denominated in
     * @return The address of the new index fund
     */

    function createIndexFund(address[] memory indexTokens, address stablecoin, bool isStablecoinEncrypted)
        external
        returns (address)
    {
        bytes32 indexFundKey = keccak256(abi.encodePacked(indexTokens, stablecoin));
        PoolKey[] memory poolKeys = new PoolKey[](indexTokens.length);
        for (uint256 i = 0; i < indexTokens.length; i++) {
            bytes32 tokenStablecoinPair = keccak256(abi.encodePacked(indexTokens[i], stablecoin));
            PoolKey memory poolKey = tokenStablecoinPairToPoolKey[tokenStablecoinPair];
            if (poolKey.currency0 == CurrencyLibrary.ADDRESS_ZERO && poolKey.currency1 == CurrencyLibrary.ADDRESS_ZERO)
            {
                revert CurrencyPairNotWhitelisted(indexTokens[i], stablecoin);
            }
            poolKeys[i] = poolKey;
        }
        if (address(indexTokensAndStablecoinToIndexFund[indexFundKey]) != address(0)) {
            revert IndexFundAlreadyExists(indexTokens, stablecoin);
        }

        IndexFundToken newIndexFundToken = new IndexFundToken(
            string.concat("IndexFundToken", "_", Strings.toString(indexFundsCount)),
            string.concat("IFT", Strings.toString(indexFundsCount))
        );
        ++indexFundsCount;

        IndexFund indexFund = new IndexFund(
            indexTokens,
            stablecoin,
            address(this),
            address(newIndexFundToken),
            marketDataFetcherProxy,
            swapsManagerProxy,
            defaultSharePrice,
            isStablecoinEncrypted,
            poolKeys
        );
        indexTokensAndStablecoinToIndexFund[indexFundKey] = indexFund;
        return address(indexFund);
    }

    /**
     * @notice Set the default share price for new index funds
     * @param newDefaultSharePrice The new default share price
     */
    function setDefaultSharePrice(uint256 newDefaultSharePrice) external onlyOwner {
        defaultSharePrice = newDefaultSharePrice;
    }

    /**
     * @notice Whitelist a token-stablecoin pair by referencing the pool key in the factory's pool map
     * @param token The token in the pair
     * @param stablecoin The stablecoin in the pair
     * @param fee The fee for the pair
     * @param tickSpacing The tick spacing for the pair
     * @param hooks The hooks for the pair
     */
    function whitelistTokenStablecoinPair(
        address token,
        address stablecoin,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    ) external onlyOwner {
        if (token < stablecoin) {
            tokenStablecoinPairToPoolKey[keccak256(abi.encodePacked(token, stablecoin))] =
                PoolKey(Currency.wrap(token), Currency.wrap(stablecoin), fee, tickSpacing, hooks);
        } else {
            tokenStablecoinPairToPoolKey[keccak256(abi.encodePacked(token, stablecoin))] =
                PoolKey(Currency.wrap(stablecoin), Currency.wrap(token), fee, tickSpacing, hooks);
        }
    }

    /**
     * @notice Remove a token-stablecoin pair from the factory's pool map
     * @param token The token in the pair
     * @param stablecoin The stablecoin in the pair
     */
    function removeWhitelistedTokenStablecoinPair(address token, address stablecoin) external onlyOwner {
        delete tokenStablecoinPairToPoolKey[keccak256(abi.encodePacked(token, stablecoin))];
    }

    /**
     * @notice Set the fee divisor for new index funds
     * @param newFeeDivisor The new fee divisor
     */
    function setFeeDivisor(uint256 newFeeDivisor) external onlyOwner {
        feeDivisor = newFeeDivisor;
    }

    function setProtocolFee(uint256 newFeeDivisor) external onlyOwner {}
}
