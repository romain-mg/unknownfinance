// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IMarketDataFetcher } from "../interfaces/IMarketDataFetcher.sol";
import { SwapsManager } from "../swaps/SwapsManager.sol";
import { IndexFundFactory } from "../IndexFundFactory.sol";
import { TFHE, eaddress, euint256 } from "fhevm/lib/TFHE.sol";
import { ConfidentialIndexFund } from "../ConfidentialIndexFund.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IndexFundToken } from "../IndexFundToken.sol";
import { ConfidentialERC20WithErrorsWrapped } from "../ERC20Encryption/ConfidentialERC20WithErrorsWrapped.sol";
import { MarketDataFetcher } from "../marketData/MarketDataFetcher.sol";

library IndexFundStateManagement {
    error AmountToSwapTooBig(uint256 amount);

    error TransferFailed(address token, eaddress from, eaddress to, euint256 amount);

    struct IndexFundState {
        uint256 totalIndexMarketCap;
        address[] indexTokens;
        PoolKey[] poolKeys;
        address swapsManagerProxy;
        uint8 numberOfSwapsToBatch;
        MarketDataFetcher marketDataFetcher;
        address indexFundFactory;
        uint256 collectedFees;
        uint8 pendingStablecoinToTokenSwapsCounter;
        uint8 pendingTokenToStablecoinSwapsCounter;
        uint128 MAX_AMOUNT_TO_SWAP;
        uint64 MAX_AMOUNT_TO_MINT_OR_BURN;
        mapping(address => uint256) tokenToPendingStablecoinSwapsAmount;
        mapping(address => uint256) tokenToPendingTokenSwapsAmount;
        ConfidentialERC20WithErrorsWrapped stablecoin;
        ERC20 decryptedStablecoin;
        IndexFundToken indexFundToken;
        uint256 sharePrice;
    }

    /**
     * @notice Preprocesses the swaps needed when minting new shares: calculates fees and distributes the
     * stablecoin amount across index tokens based on market caps.
     * @param decryptedAmount The amount of stablecoin to process
     * @return totalStablecoinIn The amount of stablecoin available for swaps after fees
     * @return feeAmount The amount of fees collected
     */
    function preprocessSwapsOnMint(
        IndexFundState storage self,
        uint256 decryptedAmount
    ) public returns (uint256 totalStablecoinIn, uint256 feeAmount) {
        address[] memory indexTokens = self.indexTokens;
        (uint256 _totalIndexMarketCap, uint256[] memory marketCaps) = IMarketDataFetcher(self.marketDataFetcher)
            .getIndexMarketCaps(indexTokens);
        self.totalIndexMarketCap = _totalIndexMarketCap;

        uint256 feeDivisor = IndexFundFactory(self.indexFundFactory).feeDivisor();
        feeAmount = decryptedAmount / feeDivisor;
        self.collectedFees += feeAmount;

        totalStablecoinIn = decryptedAmount - feeAmount;
        uint256[] memory stablecoinAmountsToSwap = _computeAmountsToSwapOnMint(
            self,
            totalStablecoinIn,
            _totalIndexMarketCap,
            marketCaps
        );
        self.pendingStablecoinToTokenSwapsCounter++;
        for (uint256 i = 0; i < indexTokens.length; i++) {
            self.tokenToPendingStablecoinSwapsAmount[indexTokens[i]] += stablecoinAmountsToSwap[i];
        }
    }

    /**
     * @notice Processes the pending stablecoin to token swaps after minting.
     * @dev Executes the swaps for each index token using the stored pending amounts.
     */
    function processSwapsOnMint(IndexFundState storage self) public {
        self.pendingStablecoinToTokenSwapsCounter = 0;
        address[] memory indexTokens = self.indexTokens;
        PoolKey[] memory poolKeys = self.poolKeys;
        for (uint256 i = 0; i < indexTokens.length; i++) {
            address currentlyProcessedToken = indexTokens[i];
            PoolKey memory poolKey = poolKeys[i];
            uint256 stablecoinAmountToSwap = self.tokenToPendingStablecoinSwapsAmount[currentlyProcessedToken];
            self.decryptedStablecoin.transfer(self.swapsManagerProxy, stablecoinAmountToSwap);
            uint256 decimals;
            if (currentlyProcessedToken == address(0)) {
                decimals = 18;
            } else {
                decimals = ERC20(currentlyProcessedToken).decimals();
            }
            uint256 tokenPrice = IMarketDataFetcher(self.marketDataFetcher).getTokenPrice(currentlyProcessedToken);
            uint256 minAmountOut = (tokenPrice * 9 * stablecoinAmountToSwap) / 10 / (10 ** decimals);

            if (stablecoinAmountToSwap > self.MAX_AMOUNT_TO_SWAP) {
                revert AmountToSwapTooBig(stablecoinAmountToSwap);
            }

            SwapsManager(self.swapsManagerProxy).swap(
                poolKey,
                uint128(stablecoinAmountToSwap),
                uint128(minAmountOut),
                block.timestamp + 1 minutes,
                true,
                address(self.decryptedStablecoin)
            );
        }
    }

    /**
     * @notice Computes the amounts of each index token to swap or redeem when burning shares. Calculates proportional amounts based on the user's
     * share of the total supply.
     * @param decryptedAmount The amount of shares being burned
     * @return tokenAmountsToRedeemOrSwap Array of token amounts to swap or redeem
     */
    function computeAmountsToSwapOrRedeemOnBurn(
        IndexFundState storage self,
        uint256 decryptedAmount
    ) public view returns (uint256[] memory tokenAmountsToRedeemOrSwap) {
        address[] memory indexTokens = self.indexTokens;
        uint256 sharesEmitted = self.indexFundToken.totalSupply();
        require(sharesEmitted > 0, "No shares emitted");
        tokenAmountsToRedeemOrSwap = new uint256[](indexTokens.length);
        for (uint256 i = 0; i < indexTokens.length; i++) {
            address token = indexTokens[i];
            uint256 tokenAmountToRedeemOrSwap;
            if (token != address(0)) {
                tokenAmountToRedeemOrSwap = (IERC20(token).balanceOf(address(this)) * decryptedAmount) / sharesEmitted;
            } else {
                // Handle the case where the token is ethereum
                tokenAmountToRedeemOrSwap = (address(this).balance * decryptedAmount) / sharesEmitted;
            }
            tokenAmountsToRedeemOrSwap[i] = tokenAmountToRedeemOrSwap;
        }
        return tokenAmountsToRedeemOrSwap;
    }

    /**
     * @notice Processes the token to stablecoin swaps when burning shares.
     * @dev Executes swaps for each index token and accumulates the stablecoin received.
     * @param tokenAmountsToSwap Array of token amounts to swap
     * @return stablecoinToSendBack Total amount of stablecoin received from swaps
     */
    function processSwapsOnBurn(
        IndexFundState storage self,
        uint256[] memory tokenAmountsToSwap
    ) public returns (uint256 stablecoinToSendBack) {
        require(self.pendingTokenToStablecoinSwapsCounter >= self.numberOfSwapsToBatch, "Not enough swaps to batch");
        address[] memory indexTokens = self.indexTokens;
        PoolKey[] memory poolKeys = self.poolKeys;

        for (uint256 i = 0; i < indexTokens.length; i++) {
            address currentlyProcessedToken = indexTokens[i];
            self.tokenToPendingTokenSwapsAmount[currentlyProcessedToken] += tokenAmountsToSwap[i];
        }
        self.pendingTokenToStablecoinSwapsCounter = 0;
        for (uint256 i = 0; i < indexTokens.length; i++) {
            address currentlyProcessedToken = indexTokens[i];
            uint256 tokenAmountToSwap = self.tokenToPendingTokenSwapsAmount[currentlyProcessedToken];
            uint256 decimals;
            if (currentlyProcessedToken == address(0)) {
                decimals = 18;
            } else {
                decimals = ERC20(currentlyProcessedToken).decimals();
            }
            uint256 tokenPrice = IMarketDataFetcher(self.marketDataFetcher).getTokenPrice(currentlyProcessedToken);
            uint256 minAmountOut = (tokenPrice * 9 * tokenAmountToSwap) / 10 / (10 ** decimals);
            if (tokenAmountToSwap > self.MAX_AMOUNT_TO_SWAP) {
                revert AmountToSwapTooBig(tokenAmountToSwap);
            }
            if (currentlyProcessedToken == address(0)) {
                stablecoinToSendBack += SwapsManager(self.swapsManagerProxy).swap{ value: tokenAmountToSwap }(
                    poolKeys[i],
                    uint128(tokenAmountToSwap),
                    uint128(minAmountOut),
                    block.timestamp + 1 minutes,
                    true,
                    currentlyProcessedToken
                );
            } else {
                IERC20(currentlyProcessedToken).transfer(self.swapsManagerProxy, tokenAmountToSwap);
                stablecoinToSendBack += SwapsManager(self.swapsManagerProxy).swap(
                    poolKeys[i],
                    uint128(tokenAmountToSwap),
                    uint128(minAmountOut),
                    block.timestamp + 1 minutes,
                    true,
                    currentlyProcessedToken
                );
            }
        }
    }

    /**
     * @notice Sends index tokens back to the user when burning shares.
     * @dev Transfers each index token to the user in proportion to their burned shares.
     * @param user The address of the user receiving the tokens
     * @param tokenAmountsToRedeemOrSwap Array of token amounts to send
     */
    function sendTokensBackOnBurn(
        IndexFundState storage self,
        address user,
        uint256[] memory tokenAmountsToRedeemOrSwap
    ) public {
        address[] memory tokens = self.indexTokens;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amountToRedeem = tokenAmountsToRedeemOrSwap[i];
            if (token == address(0)) {
                (bool transfer, ) = user.call{ value: amountToRedeem }("");
                if (!transfer) {
                    revert TransferFailed(
                        address(0),
                        TFHE.asEaddress(address(this)),
                        TFHE.asEaddress(user),
                        TFHE.asEuint256(amountToRedeem)
                    );
                }
            } else {
                bool transfer = IERC20(token).transfer(user, tokenAmountsToRedeemOrSwap[i]);
                if (!transfer) {
                    revert TransferFailed(
                        token,
                        TFHE.asEaddress(address(this)),
                        TFHE.asEaddress(user),
                        TFHE.asEuint256(amountToRedeem)
                    );
                }
            }
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
    function _computeAmountsToSwapOnMint(
        IndexFundState storage self,
        uint256 totalAmount,
        uint256 _totalIndexMarketCap,
        uint256[] memory marketCaps
    ) public view returns (uint256[] memory) {
        uint256 marketCapsLength = marketCaps.length;
        require(
            marketCapsLength == self.indexTokens.length,
            "Disrepancy between number of market caps and number of index tokens"
        );
        uint256[] memory amounts = new uint256[](marketCaps.length);
        for (uint256 i = 0; i < marketCapsLength; i++) {
            amounts[i] = (totalAmount * marketCaps[i]) / _totalIndexMarketCap;
        }
        return amounts;
    }
}
