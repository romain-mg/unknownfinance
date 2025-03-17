// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { StateLibrary } from "v4-core/src/libraries/StateLibrary.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract MarketDataFetcher is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public poolManager;
    uint256 public ETH_TOTAL_SUPPLY = 120_450_000;
    uint256 public BTC_TOTAL_SUPPLY = 21_000_000;
    function initialize(address _poolManager) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        poolManager = IPoolManager(_poolManager);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getTokenMarketCap(address token, PoolKey calldata key) internal view returns (uint256) {
        uint256 price = getPoolPrice(key);
        uint256 totalSupply = _getTokenTotalSupply(token);
        return price * totalSupply;
    }

    function getPoolPrice(PoolKey calldata key) public view returns (uint256 price) {
        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        price = (uint256(sqrtPriceX96) ** 2) / (2 ** 96);
        return price;
    }

    function _getTokenTotalSupply(address token) internal view returns (uint256) {
        if (compareStrings(ERC20(token).symbol(), "WBTC")) {
            return BTC_TOTAL_SUPPLY;
            // If token is ETH or WETH
        } else if (address(token) == address(0) || compareStrings(ERC20(token).symbol(), "WETH")) {
            return ETH_TOTAL_SUPPLY;
        }
        return ERC20(token).totalSupply();
    }

    function setETHTotalSupply(uint256 _ethTotalSupply) external onlyOwner {
        ETH_TOTAL_SUPPLY = _ethTotalSupply;
    }

    function setBTCTotalSupply(uint256 _BTCTotalSupply) external onlyOwner {
        BTC_TOTAL_SUPPLY = _BTCTotalSupply;
    }

    function compareStrings(string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
