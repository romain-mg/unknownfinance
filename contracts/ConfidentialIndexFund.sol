// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IIndexFund} from "./interfaces/IIndexFund.sol";
import {IndexFundToken} from "./IndexFundToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IndexFundFactory} from "./IndexFundFactory.sol";
import {ERC20EncryptionWrapper} from "./ERC20Encryption/ERC20EncryptionWrapper.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMarketDataFetcher} from "./interfaces/IMarketDataFetcher.sol";
import {ISwapsManager} from "./interfaces/ISwapsManager.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TFHE, euint256, ebool, einput} from "fhevm/lib/TFHE.sol";
import {ConfidentialERC20WithErrorsMintableBurnable} from
    "./ERC20Encryption/ConfidentialERC20WithErrorsMintableBurnable.sol";
import {ConfidentialERC20WithErrors} from "./ERC20Encryption/ConfidentialERC20WithErrors.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MarketDataFetcher} from "./marketData/MarketDataFetcher.sol";
import "fhevm/lib/TFHE.sol";
import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";
import {SepoliaZamaGatewayConfig} from "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";
/**
 * @title IndexFund
 * @notice This contract implements an index fund where users can mint shares by depositing stablecoin.
 */

contract ConfidentialIndexFund is
    IIndexFund,
    AccessControl,
    ReentrancyGuard,
    SepoliaZamaFHEVMConfig,
    SepoliaZamaGatewayConfig,
    GatewayCaller
{
    // Array of tokens that compose the index fund.
    address[] indexTokens;

    // Array of pool keys corresponding to each index token (used for swap operations).
    PoolKey[] poolKeys;

    // Token representing shares in the index fund.
    IndexFundToken immutable indexFundToken;

    // Address of the market data fetcher.
    MarketDataFetcher immutable marketDataFetcher;

    // Address of the swaps manager proxy.
    address immutable swapsManagerProxy;

    // Address of the index fund factory.
    address immutable indexFundFactory;

    // Stablecoin used for minting shares.
    ERC20EncryptionWrapper immutable stablecoin;

    // Transparent version of the stablecoin used for minting shares.
    ERC20 immutable decypheredStablecoin;

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

    uint8 pendingStablecoinToTokenSwapsCounter;

    uint8 pendingTokenToStablecoinSwapsCounter;

    mapping(address => uint256) tokenToPendingStablecoinSwapsAmount;
    mapping(address => uint256) tokenToPendingTokenSwapsAmount;

    modifier onlyIndexFundFactoryOwner() {
        require(msg.sender == protocolOwner, "Only the protocol owner can call this function");
        _;
    }

    /**
     * @param _indexTokens Array of token addresses that compose the index.
     * @param _stablecoin Address of the stablecoin used for deposits.
     * @param _indexFundFactory Address of the factory contract that deploys the index fund.
     * @param _indexFundToken Address of the token contract representing the index fund shares.
     * @param _marketDataFetcher Address of the protocol market data fetcher.
     * @param _swapsManagerProxy Address of the proxy used to manage token swaps.
     * @param _initialSharePrice Initial share price (in stablecoin units).
     * @param _poolKeys Array of pool keys used for token swaps.
     */
    constructor(
        address[] memory _indexTokens,
        address _stablecoin,
        address _indexFundFactory,
        address _indexFundToken,
        address _marketDataFetcher,
        address _swapsManagerProxy,
        uint256 _initialSharePrice,
        PoolKey[] memory _poolKeys
    ) {
        indexTokens = _indexTokens;
        stablecoin = ERC20EncryptionWrapper(_stablecoin);
        indexFundFactory = _indexFundFactory;
        indexFundToken = IndexFundToken(_indexFundToken);
        marketDataFetcher = MarketDataFetcher(_marketDataFetcher);
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

        // WORKS ONLY WITH UNENCRYPTED ERROR CODES -> LET IT LIKE THIS OR FIND ANOTHER SOLUTION?
        stablecoin.transferFrom(msg.sender, address(this), amount);
        uint256 transferErrorId = stablecoin.errorGetCounter() - 1;
        uint8 tramsferErrorCode = stablecoin.getErrorCodeForTransferId(transferErrorId);
        uint8 noErrorCode = uint8(ConfidentialERC20WithErrors.ErrorCodes.NO_ERROR);
        if (tramsferErrorCode != noErrorCode) {
            revert TransferFailed();
        }

        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(amount);
        uint256 requestID =
            Gateway.requestDecryption(cts, this.mintSharesCallback.selector, 0, block.timestamp + 100, false);
        addParamsAddress(requestID, msg.sender);
    }

    function mintSharesCallback(uint256 requestID, uint256 decryptedAmount) public onlyGateway {
        address[] memory params = getParamsAddress(requestID);
        address user = params[0];
        stablecoin.withdrawTo(address(this), decryptedAmount);
        (uint256 _totalIndexMarketCap, uint256[] memory marketCaps) =
            IMarketDataFetcher(marketDataFetcher).getIndexMarketCaps(indexTokens);
        totalIndexMarketCap = _totalIndexMarketCap;

        uint256 feeDivisor = IndexFundFactory(indexFundFactory).feeDivisor();
        uint256 feeAmount = decryptedAmount / feeDivisor;
        collectedFees += feeAmount;
        emit FeeCollected(feeAmount);

        uint256 stablecoinIn = decryptedAmount - feeAmount;

        uint256[] memory stablecoinAmountsToSwap =
            computeStablecoinAmountsToSwap(stablecoinIn, _totalIndexMarketCap, marketCaps);

        pendingStablecoinToTokenSwapsCounter++;

        for (uint256 i = 0; i < indexTokens.length; i++) {
            tokenToPendingStablecoinSwapsAmount[indexTokens[i]] += stablecoinAmountsToSwap[i];
        }
        if (pendingStablecoinToTokenSwapsCounter == 2) {
            pendingStablecoinToTokenSwapsCounter = 0;
            for (uint256 i = 0; i < indexTokens.length; i++) {
                address currentlyProcessedToken = indexTokens[i];
                PoolKey memory poolKey = poolKeys[i];
                uint256 stablecoinAmountToSwap = tokenToPendingStablecoinSwapsAmount[currentlyProcessedToken];

                uint256 decimals;
                if (currentlyProcessedToken == address(0)) {
                    decimals = 18;
                } else {
                    decimals = ERC20(currentlyProcessedToken).decimals();
                }
                uint256 tokenPrice = IMarketDataFetcher(marketDataFetcher).getTokenPrice(currentlyProcessedToken);
                uint256 minAmountOut = (tokenPrice * 9 * stablecoinAmountToSwap) / 10 / (10 ** decimals);

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
            emit MintSwapsPerformed();
        }

        uint256 sharesToMint = stablecoinIn / sharePrice;

        IndexFundToken(indexFundToken).mint(user, sharesToMint);
        emit SharesMinted(user, sharesToMint);
    }

    /**
     * @notice Burns a specified amount of index fund shares.
     * @dev Function implementation is pending.
     * @param encryptedAmount The encrypted amount of shares to be burned.
     * @param encryptedRedeemIndexTokens The encrypted flag indicating whether to redeem index tokens.
     * @param inputProof The proof for the encrypted amount.
     * NEED TO FIX: NO PRIVACY IN SWAPS FOR NOW, NEED TO BATCH SWAPS IN THE CASE WHERE THE USER CHOOSES TO NOT REDEEM THE TOKENS
     */
    function burnShares(einput encryptedAmount, einput encryptedRedeemIndexTokens, bytes calldata inputProof)
        external
        nonReentrant
    {
        euint256 amount = TFHE.asEuint256(encryptedAmount, inputProof);
        ebool redeemIndexTokens = TFHE.asEbool(encryptedRedeemIndexTokens, inputProof);
        euint256 encryptedIndexTokenBalance = indexFundToken.balanceOf(msg.sender);

        ebool hasUserEnoughSharesToBurn = TFHE.le(amount, encryptedIndexTokenBalance);

        // Transfer the shares to be burned from the user to this contract.
        indexFundToken.transferFrom(msg.sender, address(this), amount);
        uint256 transferErrorId = indexFundToken.errorGetCounter() - 1;
        uint8 tramsferErrorCode = indexFundToken.getErrorCodeForTransferId(transferErrorId);
        uint8 noErrorCode = uint8(ConfidentialERC20WithErrors.ErrorCodes.NO_ERROR);
        if (tramsferErrorCode != noErrorCode) {
            revert TransferFailed();
        }

        uint256[] memory cts = new uint256[](3);
        cts[0] = Gateway.toUint256(amount);
        cts[1] = Gateway.toUint256(redeemIndexTokens);
        cts[2] = Gateway.toUint256(hasUserEnoughSharesToBurn);
        uint256 requestID =
            Gateway.requestDecryption(cts, this.burnSharesCallback.selector, 0, block.timestamp + 100, false);
        addParamsAddress(requestID, msg.sender);
    }

    function burnSharesCallback(
        uint256 requestID,
        uint256 decryptedAmount,
        bool redeemIndexTokens,
        bool hasUserEnoughSharesToBurn
    ) public onlyGateway {
        address[] memory params = getParamsAddress(requestID);
        address user = params[0];
        if (!hasUserEnoughSharesToBurn) {
            revert NotEnoughSharesToBurn(user, decryptedAmount);
        }
        uint256 stablecoinToSendBack;
        indexFundToken.burn(decryptedAmount);
        emit SharesBurned(msg.sender, decryptedAmount);
        for (uint256 i = 0; i < indexTokens.length; i++) {
            address token = indexTokens[i];
            uint256 tokenAmountToRedeemOrSwap;
            if (token != address(0)) {
                tokenAmountToRedeemOrSwap =
                    (IERC20(token).balanceOf(address(this)) * decryptedAmount) / indexFundToken.totalSupply();
            } else {
                // Handle the case where the token is ethereum
                tokenAmountToRedeemOrSwap = (address(this).balance * decryptedAmount) / indexFundToken.totalSupply();
            }
            // If the user wants to redeem index tokens, transfer the corresponding amount.
            if (redeemIndexTokens) {
                IERC20(token).transfer(user, tokenAmountToRedeemOrSwap);
                emit IndexTokensRedeemed();
            } else {
                address currentlyProcessedToken = indexTokens[i];
                pendingTokenToStablecoinSwapsCounter++;
                tokenToPendingTokenSwapsAmount[currentlyProcessedToken] += tokenAmountToRedeemOrSwap;
                if (pendingTokenToStablecoinSwapsCounter == 2) {
                    pendingTokenToStablecoinSwapsCounter = 0;
                    uint256 tokenAmountToSwap = tokenToPendingTokenSwapsAmount[currentlyProcessedToken];

                    uint256 decimals;
                    if (currentlyProcessedToken == address(0)) {
                        decimals = 18;
                    } else {
                        decimals = ERC20(currentlyProcessedToken).decimals();
                    }
                    uint256 tokenPrice = IMarketDataFetcher(marketDataFetcher).getTokenPrice(currentlyProcessedToken);
                    uint256 minAmountOut = (tokenPrice * 9 * tokenAmountToSwap) / 10 / (10 ** decimals);

                    if (tokenAmountToSwap > MAX_AMOUNT_TO_SWAP) {
                        revert AmountToSwapTooBig(tokenAmountToSwap);
                    }

                    stablecoinToSendBack += ISwapsManager(swapsManagerProxy).swap(
                        poolKeys[i],
                        uint128(tokenAmountToRedeemOrSwap),
                        uint128(minAmountOut),
                        block.timestamp + 1 minutes,
                        true,
                        currentlyProcessedToken
                    );

                    emit BurnSwapsPerformed();

                    if (stablecoinToSendBack > 0) {
                        stablecoin.transferFrom(address(this), msg.sender, TFHE.asEuint256(stablecoinToSendBack));
                    }
                }
            }
        }
    }

    /**
     * @notice Computes the current value per share based on market data.
     */
    function computeShareValue() external view returns (uint256 shareValue) {
        uint256 totalValue = 0;
        for (uint256 i = 0; i < indexTokens.length; i++) {
            uint256 tokenPrice = IMarketDataFetcher(marketDataFetcher).getTokenPrice(indexTokens[i]);
            uint256 tokenAmount = IERC20(indexTokens[i]).balanceOf(address(this));
            uint256 tokenDecimals;
            if (indexTokens[i] == address(0)) {
                tokenDecimals = 18;
            } else {
                tokenDecimals = ERC20(indexTokens[i]).decimals();
            }
            totalValue += (tokenPrice * tokenAmount) / (10 ** tokenDecimals);
            shareValue = totalValue / indexFundToken.totalSupply();
        }
    }

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
    function getStablecoin() public view returns (ERC20EncryptionWrapper) {
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
        if (!decypheredStablecoin.transfer(protocolOwner, collectedFees)) {
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
                indexTokens[i], uint160(amounts[i]), uint48(block.timestamp + 1 days)
            );
        }
        return amounts;
    }
}
