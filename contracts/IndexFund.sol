// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IIndexFund } from "./interfaces/IIndexFund.sol";
import { IndexFundToken } from "./IndexFundToken.sol";
import { IERC20 } from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { EIP1967Proxy } from "@openzeppelin-contracts/proxy/beacon/EIP1967Proxy.sol";

contract IndexFund is IIndexFund {
    // TODO: add mapping (encrypted token => mapping(decrypted token => poolKey))
    address[] indexTokens;
    PoolKey[] poolKeys;

    IERC20 indexFundToken;

    address marketDataFetcherProxy;

    address swapsManagerProxy;

    address indexFundFactory;

    IERC20 stablecoin;

    uint256 sharePrice;
100
    uint256 feeDivisor;

    uint256 totalIndexMarketCap;

    address protocolOwner;

    uint256 collectedFees;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(address indexed user, uint256 indexed amount, uint256 indexed stablecoinIn);

    event SharesBurned(address indexed user, uint256 indexed amount);

    constructor(
        address[] memory _indexTokens,
        address _stablecoin,
        address _indexFundFactory,
        address _indexFundToken,
        address _marketDataFetcherProxy,
        address _swapsManagerProxy,
        uint256 _initialSharePrice,
        address _protocolOwner
    ) {
        indexTokens = _indexTokens;
        stablecoin = IERC20(_stablecoin);
        indexFundFactory = _indexFundFactory;
        indexFundToken = IERC20(_indexFundToken);
        marketDataFetcherProxy = _marketDataFetcherProxy;
        swapsManagerProxy = _swapsManagerProxy;
        sharePrice = _initialSharePrice;
        protocolOwner = _protocolOwner;
        feeDivisor = IndexFundFactory(_indexFundFactory).feeDivisor();
    }

    // TODO: add logic to handle encrypted tokens
    function mintShares(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        if (stablecoin.allowance(msg.sender, address(this)) < amount) {
            revert InsufficientAllowance(address(stablecoin));
        }
        stablecoin.transferFrom(msg.sender, address(this), amount);
        (uint256 totalIndexMarketCap, uint256[] memory marketCaps) = EIP1967Proxy(marketDataFetcherProxy)
            .getIndexMarketCaps(indexTokens, poolKeys);
        uint256 
        uint256 feeAmount = amount / feeDivisor;
        collectedFees += feeAmount;
        emit FeeCollected(msg.sender, feeAmount);
        uint256 stablecoinIn = amount - feeAmount;
        uint256[] memory stablecoinAmountsToSwap = computeStablecoinAmountsToSwap(stablecoinIn, totalIndexMarketCap, marketCaps);
        for (uint256 i = 0; i < indexTokens.length; i++) {
            swapsManager.approveTokenWithPermit2(indexTokens[i], uint160);
            // TODO: set a relevant minimum amount out
            swapsManager.swapExactInputSingle(
                poolKeys[i],
                stablecoinAmountsToSwap[i],
                0,
                block.timestamp + 1 minutes
            );
        }
        uint256 sharesToMint = stablecoinAmountsToSwap / sharePrice;
        IndexFundToken(indexFundToken).mint(msg.sender, sharesToMint);
        emit SharesMinted(msg.sender, sharesToMint, stablecoinIn);
    }

    function burnShares(uint256 amount) external {}

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

    function sendFeesToProtocolOwner() public {}

    function computeStablecoinAmountsToSwap(
        uint256 totalAmount,
        uint256 totalIndexMarketCap,
        uint256[] memory marketCaps
    ) internal pure returns (uint256[] memory) {
        uint256 marketCapsLength = marketCaps.length;
        require(
            marketCapsLength== indexTokens.length,
            "Disrepancy between number of market caps and number of index tokens"
        );
        uint256[] memory totalAmounts = new uint256[](marketCaps.length);
        for (uint256 i = 0; i < marketCapsLength, i++) {
            assembly {
                let marketCap := mload(add(marketCaps.slot, i))
                mstore(add(totalAmount.slot, i), div(mul(totalAmount, marketCap), totalIndexMarketCap))
            }
            swapManager.approveTokenWithPermit2(indexTokens[i], uint160(totalAmounts[i]), uint48(block.timestamp + 1 days));
        }
        return totalAmounts;
    }
}
