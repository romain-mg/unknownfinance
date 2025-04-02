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
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { TFHE, euint256, ebool, einput } from "fhevm/lib/TFHE.sol";
import { ConfidentialERC20WithErrorsMintable } from "./ERC20Encryption/ConfidentialERC20WithErrorsMintable.sol";
import { ConfidentialERC20WithErrors } from "./ERC20Encryption/ConfidentialERC20WithErrors.sol";
import { IERC20EncryptionWrapper } from "./interfaces/IERC20EncryptionWrapper.sol";
/**
 * @title IndexFund
 * @notice This contract implements an index fund where users can mint shares by depositing stablecoin.
 */
contract ConfidentialIndexFund is IIndexFund, AccessControl, ReentrancyGuard {
    // Array of tokens that compose the index fund.
    address[] indexTokens;

    // Array of pool keys corresponding to each index token (used for swap operations).
    PoolKey[] poolKeys;

    // Token representing shares in the index fund.
    IndexFundToken immutable indexFundToken;

    // Address of the market data fetcher proxy.
    address immutable marketDataFetcherProxy;

    // Address of the swaps manager proxy.
    address immutable swapsManagerProxy;

    // Address of the index fund factory.
    address immutable indexFundFactory;

    // Stablecoin used for minting shares.
    ERC20EncryptionWrapper immutable stablecoin;

    // Current share price in terms of the stablecoin.
    uint256 sharePrice;

    // Total market capitalization of all index tokens.
    uint256 totalIndexMarketCap;

    // Owner of the protocol, as defined by the index fund factory.
    address protocolOwner;

    // Accumulated fees collected from mint operations.
    uint256 collectedFees;

    // Maximum stablecoin amount allowed to be swapped in one transaction.
    uint128 constant MAX_AMOUNT_TO_SWAP = 2 ** 128 - 1;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(address indexed user, uint256 indexed amount, uint256 indexed stablecoinIn);

    event SharesBurned(address indexed user, uint256 indexed amount);

    modifier onlyIndexFundFactoryOwner() {
        require(msg.sender == protocolOwner, "Only the protocol owner can call this function");
        _;
    }

    /**
     * @param _indexTokens Array of token addresses that compose the index.
     * @param _stablecoin Address of the stablecoin used for deposits.
     * @param _indexFundFactory Address of the factory contract that deploys the index fund.
     * @param _indexFundToken Address of the token contract representing the index fund shares.
     * @param _marketDataFetcherProxy Address of the proxy used to fetch market data.
     * @param _swapsManagerProxy Address of the proxy used to manage token swaps.
     * @param _initialSharePrice Initial share price (in stablecoin units).
     * @param _poolKeys Array of pool keys used for token swaps.
     */
    constructor(
        address[] memory _indexTokens,
        address _stablecoin,
        address _indexFundFactory,
        address _indexFundToken,
        address _marketDataFetcherProxy,
        address _swapsManagerProxy,
        uint256 _initialSharePrice,
        PoolKey[] memory _poolKeys
    ) {
        indexTokens = _indexTokens;
        stablecoin = ERC20EncryptionWrapper(_stablecoin);
        indexFundFactory = _indexFundFactory;
        indexFundToken = IndexFundToken(_indexFundToken);
        marketDataFetcherProxy = _marketDataFetcherProxy;
        swapsManagerProxy = _swapsManagerProxy;
        sharePrice = _initialSharePrice;
        protocolOwner = IndexFundFactory(_indexFundFactory).owner();
        poolKeys = _poolKeys;
    }

    /**
     * @notice Mints new index fund shares by depositing a specified amount of stablecoin.
     * @dev Handles fee deduction, token swaps, and share minting.
     * It fetches market data and calculates swap amounts based on token market caps.
     * @param encryptedAmount The encrypted amount of stablecoin the user is depositing.
     */
    function mintShares(einput encryptedAmount, bytes calldata inputProof) external nonReentrant {
        euint256 amount = TFHE.asEuint256(encryptedAmount, inputProof);

        stablecoin.transferFrom(msg.sender, address(this), amount);
        uint256 transferErrorId = stablecoin.errorGetCounter() - 1;
        uint8 tramsferErrorCode = stablecoin.getErrorCodeForTransferId(transferErrorId);
        uint8 noErrorCode = uint8(ConfidentialERC20WithErrors.ErrorCodes.NO_ERROR);
        if (tramsferErrorCode != noErrorCode) {
            revert TransferFailed();
        }
        // then unwrap the stablecoin
        stablecoin.withdrawTo(address(this), amount);

        (uint256 _totalIndexMarketCap, uint256[] memory marketCaps) = IMarketDataFetcher(marketDataFetcherProxy)
            .getIndexMarketCaps(indexTokens, poolKeys);
        totalIndexMarketCap = _totalIndexMarketCap;

        uint256 feeDivisor = IndexFundFactory(indexFundFactory).feeDivisor();

        // need to decypher amount to pursue

        // uint256 feeAmount = amount / feeDivisor;
        // collectedFees += feeAmount;
        // emit FeeCollected(msg.sender, feeAmount);

        // uint256 stablecoinIn = amount - feeAmount;

        // uint256[] memory stablecoinAmountsToSwap = computeStablecoinAmountsToSwap(
        //     stablecoinIn,
        //     _totalIndexMarketCap,
        //     marketCaps
        // );

        // for (uint256 i = 0; i < indexTokens.length; i++) {
        //     PoolKey memory poolKey = poolKeys[i];
        //     uint256 stablecoinAmountToSwap = stablecoinAmountsToSwap[i];

        //     // Fetch the token price to compute a minimum acceptable output (with 10% slippage).
        //     uint256 tokenPrice = IMarketDataFetcher(marketDataFetcherProxy).getTokenPrice(indexTokens[i], poolKey);
        //     uint256 minAmountOut = (tokenPrice * stablecoinAmountToSwap * 9) / 10;

        //     if (stablecoinAmountToSwap > MAX_AMOUNT_TO_SWAP) {
        //         revert AmountToSwapTooBig(stablecoinAmountToSwap);
        //     }

        //     ISwapsManager(swapsManagerProxy).swap(
        //         poolKey,
        //         uint128(stablecoinAmountToSwap),
        //         uint128(minAmountOut),
        //         block.timestamp + 1 minutes,
        //         true,
        //         address(stablecoin)
        //     );
        // }

        // uint256 sharesToMint = stablecoinIn / sharePrice;

        // IndexFundToken(indexFundToken).mint(msg.sender, sharesToMint);
    }

    /**
     * @notice Burns a specified amount of index fund shares.
     * @dev Function implementation is pending.
     * @param amount The number of shares to burn.
     */
    function burnShares(uint256 amount, bool redeemIndexTokens) external {
        require(amount > 0, "Amount must be greater than 0");

        euint256 encryptedAmount = TFHE.asEuint256(amount);
        // require(TFHE.le(encryptedAmount, indexFundToken.balanceOf(msg.sender)), "Amount too big");
    }

    /**
     * @notice Computes the current value per share based on market data.
     * @dev Function implementation is pending.
     */
    function computeShareValue() external {}

    /**
     * @notice Retrieves the list of index token addresses.
     * @return An array of addresses representing the index tokens.
     */
    function getIndexTokens() public view returns (address[] memory) {
        return indexTokens;
    }

    /**
     * @notice Retrieves the index fund token contract instance.
     * @return The IndexFundToken contract.
     */
    function getIndexFundToken() public view returns (IndexFundToken) {
        return indexFundToken;
    }

    /**
     * @notice Retrieves the stablecoin contract used by the index fund.
     * @return The IERC20 stablecoin contract.
     */
    function getStablecoin() public view returns (IERC20EncryptionWrapper) {
        return stablecoin;
    }

    /**
     * @notice Transfers the collected fees to the protocol owner.
     * @dev Only callable by the protocol owner and protected against reentrancy.
     */
    function sendFeesToProtocolOwner() public onlyIndexFundFactoryOwner nonReentrant {
        require(collectedFees > 0, "No fees to send");
        // Reset fees before transferring to prevent reentrancy.
        collectedFees = 0;
        if (stablecoin.transfer(protocolOwner, collectedFees) == false) {
            revert TransferFailed();
        }
    }

    /**
     * @notice Computes the distribution of stablecoin amounts to swap for each index token.
     * @dev Calculates the swap amount for each token based on its market cap relative to the total index market cap.
     * Also approves each token for swapping via the swaps manager.
     * @param totalAmount The total stablecoin amount available for swaps.
     * @param _totalIndexMarketCap The total market capitalization of the index tokens.
     * @param marketCaps An array of market capitalizations for each index token.
     * @return An array containing the stablecoin amount allocated for each token swap.
     */
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
            // Calculate proportional swap amount.
            amounts[i] = (totalAmount * marketCaps[i]) / _totalIndexMarketCap;
            // Approve token for swapping with a permit valid for 1 day.
            ISwapsManager(swapsManagerProxy).approveTokenWithPermit2(
                indexTokens[i],
                uint160(amounts[i]),
                uint48(block.timestamp + 1 days)
            );
        }
        return amounts;
    }
}
