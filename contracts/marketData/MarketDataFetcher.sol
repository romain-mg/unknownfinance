// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey, Currency } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "@uniswap/v4-core/src/types/PoolId.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IMarketDataFetcher } from "../interfaces/IMarketDataFetcher.sol";

contract MarketDataFetcher is Initializable, UUPSUpgradeable, OwnableUpgradeable, IMarketDataFetcher {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public poolManager;
    uint256 public ETH_TOTAL_SUPPLY = 120_450_000;
    uint256 public BTC_TOTAL_SUPPLY = 21_000_000;

    function setETHTotalSupply(uint256 _ethTotalSupply) external onlyOwner {
        ETH_TOTAL_SUPPLY = _ethTotalSupply;
    }

    function setBTCTotalSupply(uint256 _BTCTotalSupply) external onlyOwner {
        BTC_TOTAL_SUPPLY = _BTCTotalSupply;
    }

    function initialize(address _poolManager) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        poolManager = IPoolManager(_poolManager);
    }

    /**
     * @notice Calculates the total market capitalization for an index and individual token market caps.
     * @dev Iterates through each token and its corresponding pool key to compute market cap.
     * @param indexTokenAddresses Array of token addresses.
     * @param keys Array of corresponding pool keys.
     * @return totalMarketCap The aggregated market capitalization.
     * @return marketCaps Array of market capitalization values for each token.
     */
    function getIndexMarketCaps(
        address[] calldata indexTokenAddresses,
        PoolKey[] calldata keys
    ) public view returns (uint256 totalMarketCap, uint256[] memory marketCaps) {
        require(indexTokenAddresses.length == keys.length, "Missing token addresses or keys");
        totalMarketCap = 0;
        marketCaps = new uint256[](indexTokenAddresses.length);
        for (uint i = 0; i < indexTokenAddresses.length; i++) {
            totalMarketCap += getTokenMarketCap(indexTokenAddresses[i], keys[i]);
            marketCaps[i] = getTokenMarketCap(indexTokenAddresses[i], keys[i]);
        }
        return (totalMarketCap, marketCaps);
    }

    /**
     * @notice Retrieves the market cap of a token in stablecoin-denominated terms.
     * @dev Uses the token's scaled price and total supply to calculate the market cap.
     * @param token The token address.
     * @param key The corresponding Uniswap v4 pool key.
     * @return The market cap of the token.
     */
    function getTokenMarketCap(address token, PoolKey calldata key) public view returns (uint256) {
        uint256 scaledTokenPrice = getScaledTokenPrice(token, key);
        uint256 totalSupply = _getTokenTotalSupply(token);
        return (scaledTokenPrice ** 2 * totalSupply) / (2 ** 96);
    }

    function getTokenPrice(address token, PoolKey calldata key) public view returns (uint256) {
        uint256 price = getScaledTokenPrice(token, key);
        return price ** 2 / 2 ** 96;
    }

    /**
     * @notice Computes the scaled token price relative to the pool's stablecoin.
     * @dev Determines the token's position in the pool key (currency0 or currency1) to adjust price.
     * @param token The token address.
     * @param key The pool key for the token.
     * @return The scaled token price.
     */
    function getScaledTokenPrice(address token, PoolKey calldata key) internal view returns (uint256) {
        uint160 scaledPoolPrice = getScaledPoolPrice(key);
        uint256 scaledTokenPrice;
        if (Currency.unwrap(key.currency0) == token) {
            scaledTokenPrice = scaledPoolPrice;
        } else {
            scaledTokenPrice = 1 / scaledPoolPrice;
        }
        return scaledTokenPrice;
    }

    /**
     * @notice Retrieves the scaled pool price from the pool manager.
     * @dev Extracts the sqrtPriceX96 value from the pool's slot0.
     * @param key The pool key.
     * @return price The pool's sqrtPriceX96.
     */
    function getScaledPoolPrice(PoolKey calldata key) internal view returns (uint160 price) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        return sqrtPriceX96;
    }

    function compareStrings(string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    /**
     * @notice Retrieves the total supply for a given token.
     * @dev Returns a preset supply for WBTC and WETH; otherwise, uses the token's ERC20 totalSupply.
     * @param token The token address.
     * @return The total supply of the token.
     */
    function _getTokenTotalSupply(address token) internal view returns (uint256) {
        if (compareStrings(ERC20(token).symbol(), "WBTC")) {
            return BTC_TOTAL_SUPPLY;
        } else if (address(token) == address(0) || compareStrings(ERC20(token).symbol(), "WETH")) {
            return ETH_TOTAL_SUPPLY;
        }
        return ERC20(token).totalSupply();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
