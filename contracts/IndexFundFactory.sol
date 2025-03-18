// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import { IndexFund } from "./IndexFund.sol";
import { IIndexFundFactory } from "./interfaces/IIndexFundFactory.sol";
import { Ownable } from "@openzeppelin-contracts/access/Ownable.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { IndexFundToken } from "./IndexFundToken.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IIndexFund } from "./interfaces/IIndexFund.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract IndexFuncFactory is IIndexFundFactory, Ownable {
    mapping(bytes32 => PoolKey) public tokenStablecoinPairToPoolKey;

    mapping(bytes32 => IIndexFund) public indexTokensAndStablecoinToIndexFund;

    address public swapsManagerProxy;

    uint96 indexFundsCount;

    address public marketDataFetcherProxy;

    uint256 defaultSharePrice;

    constructor(
        address _swapsManagerProxy,
        address _markerDataFetcherProxy,
        uint256 _defaultSharePrice
    ) Ownable(msg.sender) {
        swapsManagerProxy = _swapsManager;
        marketDataFetcherProxy = _markerDataFetcher;
        defaultSharePrice = _defaultSharePrice;
    }
    /**
     * @notice Create a new index fund
     * @dev The function first checks that a pool is referenced in the factory's pool map for each token-stablecoin pair
     * @param indexTokens The tokens that make up the index fund
     * @param stablecoin The stablecoin that the index fund is denominated in
     * @return The address of the new index fund
     */
    function createIndexFund(address[] memory indexTokens, address memory stablecoin) external returns (address) {
        for (uint256 i = 0; i < indexTokens.length; i++) {
            bytes32 poolKeyMapKey = keccak256(abi.encodePacked(indexTokens[i], stablecoin));
            PoolKey poolKey = tokenStablecoinPairToPoolKey[poolKeyMapKey];
            if (poolKey.currency0 == Currency.ADDRESS_ZERO && poolKey.currency1 == Currency.ADDRESS_ZERO) {
                revert CurrencyPairNotWhitelisted(indexTokens[i], stablecoin);
            }
            bytes32 indexFundKey = keccak256(abi.encodePacked(indexTokens, stablecoin));
            if (tokensAndStablecoinToIndexFund[indexFundKey] != address(0)) {
                revert IndexFundAlreadyExists(indexTokens, stablecoin);
            }
        }
        IndexFundToken newIndexFundToken = new IndexFundToken(
            string.concat("IndexFundToken", "_", Strings.toString(indexFundsCount)),
            string.concat("IFT", Strings.toString(indexFundsCount))
        );
        ++indexFundsCount;
        IndexFund indexFund = new IndexFund(
            indexTokens,
            stablecoin,
            newIndexFundToken,
            marketDataFetcher,
            swapsManager,
            defaultSharePrice
        );
        tokensAndStablecoinToIndexFund[indexFundKey] = indexFund;
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
     * @param isStablecoinCurrency0 Whether the stablecoin is currency0 in the pair
     */
    function whitelistTokenStablecoinPair(
        address token,
        address stablecoin,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks,
        bool isStablecoinCurrency0
    ) external onlyOwner {
        if (isStablecoinCurrency0) {
            tokenStablecoinPairToPoolKey[keccak256(abi.encodePacked(token, stablecoin))] = PoolKey(
                Currency(stablecoin),
                Currency(token),
                fee,
                tickSpacing,
                hooks
            );
        } else {
            tokenStablecoinPairToPoolKey[keccak256(abi.encodePacked(token, stablecoin))] = PoolKey(
                Currency(token),
                Currency(stablecoin),
                fee,
                tickSpacing,
                hooks
            );
        }
    }

    /**
     * @notice Remove a token-stablecoin pair from the factory's pool map
     * @param token The token in the pair
     * @param stablecoin The stablecoin in the pair
     */
    function removeWhitelistedTokenStablecoinPair(address token) external onlyOwner {
        delete tokenStablecoinPairToPoolKey[keccak256(abi.encodePacked(token, stablecoin))];
    }
}
