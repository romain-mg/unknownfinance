// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IIndexFund } from "./interfaces/IIndexFund.sol";
import { IndexFundToken } from "./IndexFundToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IndexFundFactory } from "./IndexFundFactory.sol";
import { ERC20EncryptionWrapper } from "./ERC20Encryption/ERC20EncryptionWrapper.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IMarketDataFetcher } from "./interfaces/IMarketDataFetcher.sol";
import { ISwapsManager } from "./interfaces/ISwapsManager.sol";

contract IndexFund is IIndexFund, AccessControl {
    address[] indexTokens;

    PoolKey[] poolKeys;

    IndexFundToken indexFundToken;

    address marketDataFetcherProxy;

    bool isStablecoinEncrypted;

    address swapsManagerProxy;

    address indexFundFactory;

    IERC20 stablecoin;

    uint256 sharePrice;

    uint256 feeDivisor;

    uint256 totalIndexMarketCap;

    address protocolOwner;

    uint256 collectedFees;

    uint64 constant MAX_SHARES_AMOUNT_TO_MINT = 0xffffffffffffffff;

    uint128 constant MAX_AMOUNT_TO_SWAP = 0xffffffffffffffffffffffffffffffff;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(address indexed user, uint256 indexed amount, uint256 indexed stablecoinIn);

    event SharesBurned(address indexed user, uint256 indexed amount);

    modifier onlyIndexFundFactoryOwner() {
        require(msg.sender == protocolOwner, "Only the protocol owner can call this function");
        _;
    }

    constructor(
        address[] memory _indexTokens,
        address _stablecoin,
        address _indexFundFactory,
        address _indexFundToken,
        address _marketDataFetcherProxy,
        address _swapsManagerProxy,
        uint256 _initialSharePrice,
        bool _isStablecoinEncrypted
    ) {
        indexTokens = _indexTokens;
        stablecoin = IERC20(_stablecoin);
        indexFundFactory = _indexFundFactory;
        indexFundToken = IndexFundToken(_indexFundToken);
        marketDataFetcherProxy = _marketDataFetcherProxy;
        swapsManagerProxy = _swapsManagerProxy;
        sharePrice = _initialSharePrice;
        feeDivisor = IndexFundFactory(_indexFundFactory).feeDivisor();
        isStablecoinEncrypted = _isStablecoinEncrypted;
        protocolOwner = IndexFundFactory(_indexFundFactory).owner();
    }

    // TODO: add logic to handle encrypted tokens
    function mintShares(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        if (stablecoin.allowance(msg.sender, address(this)) < amount) {
            revert InsufficientAllowance(address(stablecoin));
        }
        stablecoin.transferFrom(msg.sender, address(this), amount);
        if (isStablecoinEncrypted) {
            ERC20EncryptionWrapper(address(stablecoin)).withdrawTo(address(this), amount);
        }
        (uint256 _totalIndexMarketCap, uint256[] memory marketCaps) = IMarketDataFetcher(marketDataFetcherProxy)
            .getIndexMarketCaps(indexTokens, poolKeys);
        totalIndexMarketCap = _totalIndexMarketCap;
        uint256 feeAmount = amount / feeDivisor;
        collectedFees += feeAmount;
        emit FeeCollected(msg.sender, feeAmount);
        uint256 stablecoinIn = amount - feeAmount;
        uint256[] memory stablecoinAmountsToSwap = computeStablecoinAmountsToSwap(
            stablecoinIn,
            _totalIndexMarketCap,
            marketCaps
        );
        for (uint256 i = 0; i < indexTokens.length; i++) {
            PoolKey memory poolKey = poolKeys[i];
            uint256 stablecoinAmountToSwap = stablecoinAmountsToSwap[i];
            uint256 tokenPrice = IMarketDataFetcher(marketDataFetcherProxy).getTokenPrice(indexTokens[i], poolKey);
            uint256 minAmountOut = (tokenPrice * stablecoinAmountToSwap * 9) / 10;
            if (stablecoinAmountToSwap > MAX_AMOUNT_TO_SWAP) {
                revert AmountToSwapTooBig(stablecoinAmountToSwap);
            }
            ISwapsManager(swapsManagerProxy).swap(
                poolKey,
                uint128(stablecoinAmountToSwap),
                uint128(minAmountOut),
                block.timestamp + 1 minutes,
                true,
                address(stablecoin)
            );
        }
        uint256 sharesToMint = stablecoinIn / sharePrice;
        if (sharesToMint > MAX_SHARES_AMOUNT_TO_MINT) {
            revert SharesToMintAmountTooBig(sharesToMint);
        }
        IndexFundToken(indexFundToken).mint(msg.sender, uint64(sharesToMint));
        emit SharesMinted(msg.sender, sharesToMint, stablecoinIn);
    }

    function burnShares(uint256 amount) external {}

    function getIndexTokens() public view returns (address[] memory) {
        return indexTokens;
    }

    function getIndexFundToken() public view returns (IndexFundToken) {
        return indexFundToken;
    }

    function getStablecoin() public view returns (IERC20) {
        return stablecoin;
    }

    function sendFeesToProtocolOwner() public onlyIndexFundFactoryOwner {
        require(collectedFees > 0, "No fees to send");
        stablecoin.transfer(protocolOwner, collectedFees);
        collectedFees = 0;
    }

    function computeStablecoinAmountsToSwap(
        uint256 totalAmount,
        uint256 _totalIndexMarketCap,
        uint256[] memory marketCaps
    ) internal returns (uint256[] memory) {
        uint256 marketCapsLength = marketCaps.length;
        require(
            marketCapsLength == indexTokens.length,
            "Disrepancy between number of market caps and number of index tokens"
        );
        uint256[] memory amounts = new uint256[](marketCaps.length);
        for (uint256 i = 0; i < marketCapsLength; i++) {
            amounts[i] = (totalAmount * marketCaps[i]) / _totalIndexMarketCap;
            ISwapsManager(swapsManagerProxy).approveTokenWithPermit2(
                indexTokens[i],
                uint160(amounts[i]),
                uint48(block.timestamp + 1 days)
            );
        }
        return amounts;
    }
}
