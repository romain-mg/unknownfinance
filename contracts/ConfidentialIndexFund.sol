// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IIndexFund} from "./interfaces/IIndexFund.sol";
import {IndexFundToken} from "./IndexFundToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IndexFundFactory} from "./IndexFundFactory.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMarketDataFetcher} from "./interfaces/IMarketDataFetcher.sol";
import {SwapsManager} from "./swaps/SwapsManager.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TFHE, euint64, ebool, einput} from "fhevm/lib/TFHE.sol";
import {ConfidentialERC20WithErrorsMintableBurnable} from
    "./ERC20Encryption/ConfidentialERC20WithErrorsMintableBurnable.sol";
import {ConfidentialERC20WithErrorsWrapped} from "./ERC20Encryption/ConfidentialERC20WithErrorsWrapped.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MarketDataFetcher} from "./marketData/MarketDataFetcher.sol";
import "fhevm/lib/TFHE.sol";
import {SepoliaZamaFHEVMConfig} from "fhevm/config/ZamaFHEVMConfig.sol";
import {SepoliaZamaGatewayConfig} from "fhevm/config/ZamaGatewayConfig.sol";
import {ConfidentialERC20WithErrors} from "@httpz-contracts/token/ERC20/extensions/ConfidentialERC20WithErrors.sol";
import "fhevm/gateway/GatewayCaller.sol";
import {IndexFundStateManagement} from "./lib/IndexFundStateManagement.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title ConfidentialIndexFund
 * @notice Implements a confidential index fund that enables private investment in a basket of tokens
 * @dev This contract provides a privacy-preserving way to invest in multiple tokens through a single
 * index fund. It uses Fully Homomorphic Encryption (FHE) to maintain confidentiality of user balances,
 * transactions, and fund operations.
 *
 * Key features:
 * - Confidential minting and burning of index fund shares
 * - Private stablecoin deposits and withdrawals
 * - Encrypted balance tracking and transfers
 * - Automatic token swaps based on market cap weights
 * - Support for both index token and stablecoin redemption paths
 * - Integration with Uniswap V4 for token swaps
 * - Market data integration for price feeds and market caps
 *
 * Security features:
 * - Reentrancy protection
 * - Access control for administrative functions
 * - Encrypted state management
 * - Gateway-based decryption for sensitive operations
 * - Batch processing for swaps to enhance privacy
 *
 * The contract maintains privacy while providing full functionality of a traditional index fund,
 * allowing users to:
 * 1. Deposit stablecoins to mint index fund shares
 * 2. Burn shares to redeem either underlying tokens or stablecoins
 * 3. Track their encrypted balances and transactions
 * 4. Participate in the fund without revealing their positions
 */
contract ConfidentialIndexFund is
    IIndexFund,
    AccessControl,
    ReentrancyGuard,
    SepoliaZamaFHEVMConfig,
    SepoliaZamaGatewayConfig,
    GatewayCaller
{
    using IndexFundStateManagement for IndexFundStateManagement.IndexFundState;

    IndexFundStateManagement.IndexFundState private indexFundState;

    // Owner of the protocol, as defined by the index fund factory.
    address protocolOwner;

    uint256 private constant USDC_DECIMALS = 1e6;

    mapping(address => uint256[]) userToTokenWithdrawableAmounts;

    mapping(address => bool) redeemIndexTokenForPendingWithdrawal;

    mapping(address => euint64) userToPendingStablecoinTransfer;

    mapping(address => uint64) userToPendingMintAmount;

    modifier onlyIndexFundFactoryOwner() {
        require(msg.sender == protocolOwner, "Only the protocol owner can call this function");
        _;
    }

    /**
     * @param _indexTokens Array of token addresses that compose the index.
     * @param _stablecoin Address of the stablecoin used for deposits.
     * @param _decypheredStablecoin Address of the transparent version of the stablecoin.
     * @param _indexFundFactory Address of the factory contract that deploys the index fund.
     * @param _marketDataFetcher Address of the protocol market data fetcher.
     * @param _swapsManagerProxy Address of the proxy used to manage token swaps.
     * @param _initialSharePrice Initial share price (in stablecoin units).
     * @param _poolKeys Array of pool keys used for token swaps.
     * @param currentIndexFundsCount Current index funds count coming from the factory
     */
    constructor(
        address[] memory _indexTokens,
        address _stablecoin,
        address _decypheredStablecoin,
        address _indexFundFactory,
        address _marketDataFetcher,
        address _swapsManagerProxy,
        uint256 _initialSharePrice,
        PoolKey[] memory _poolKeys,
        uint8 _numberOfSwapsToBatch,
        uint96 currentIndexFundsCount
    ) {
        protocolOwner = IndexFundFactory(_indexFundFactory).owner();

        indexFundState.poolKeys = _poolKeys;
        indexFundState.marketDataFetcher = MarketDataFetcher(_marketDataFetcher);
        indexFundState.swapsManagerProxy = _swapsManagerProxy;
        indexFundState.MAX_AMOUNT_TO_SWAP = type(uint128).max;
        indexFundState.MAX_AMOUNT_TO_MINT_OR_BURN = type(uint64).max;
        indexFundState.indexFundFactory = _indexFundFactory;
        indexFundState.indexTokens = _indexTokens;
        indexFundState.stablecoin = ConfidentialERC20WithErrorsWrapped(_stablecoin);
        indexFundState.decryptedStablecoin = ERC20(_decypheredStablecoin);
        indexFundState.indexFundToken = new IndexFundToken(
            string.concat("IndexFundToken", "_", Strings.toString(currentIndexFundsCount)),
            string.concat("IFT", Strings.toString(currentIndexFundsCount))
        );
        indexFundState.sharePrice = _initialSharePrice;
        indexFundState.numberOfSwapsToBatch = _numberOfSwapsToBatch;
    }

    /**
     * @notice Mints new index fund shares by depositing a specified amount of stablecoin.
     * @dev Handles fee deduction, token swaps, and share minting.
     * It fetches market data and calculates swap amounts based on token market caps.
     * @param encryptedAmount The encrypted amount of stablecoin the user is depositing.
     * @param inputProof The proof for the encrypted amount.
     */
    function mintShares(einput encryptedAmount, bytes calldata inputProof) external nonReentrant {
        ConfidentialERC20WithErrorsWrapped stablecoin = indexFundState.stablecoin;
        euint64 amount = TFHE.asEuint64(encryptedAmount, inputProof);
        TFHE.allowTransient(amount, address(stablecoin));
        stablecoin.transferFrom(msg.sender, address(this), amount);
        require(stablecoin.errorGetCounter() > 0, "No error recorded");
        uint256 transferErrorId = stablecoin.errorGetCounter() - 1;
        euint8 transferErrorCode = stablecoin.getErrorCodeForTransferId(transferErrorId);
        uint256[] memory cts = new uint256[](2);
        cts[0] = Gateway.toUint256(transferErrorCode);
        cts[1] = Gateway.toUint256(amount);
        uint256 requestID =
            Gateway.requestDecryption(cts, this.mintSharesCallback.selector, 0, block.timestamp + 100, false);
        addParamsAddress(requestID, msg.sender);
    }

    /**
     * @notice Burns a specified amount of index fund shares.
     * @dev Function implementation is pending.
     * @param encryptedAmount The encrypted amount of shares to be burned.
     * @param encryptedRedeemIndexTokens The encrypted flag indicating whether to redeem index tokens.
     * @param inputProof The proof for the encrypted amount.
     */
    function burnShares(einput encryptedAmount, einput encryptedRedeemIndexTokens, bytes calldata inputProof)
        external
        nonReentrant
    {
        euint64 amount = TFHE.asEuint64(encryptedAmount, inputProof);
        ebool redeemIndexTokens = TFHE.asEbool(encryptedRedeemIndexTokens, inputProof);
        IndexFundToken indexFundToken = indexFundState.indexFundToken;

        euint64 encryptedIndexTokenBalance = indexFundToken.balanceOfAllow(msg.sender);

        ebool hasUserEnoughSharesToBurn = TFHE.le(amount, encryptedIndexTokenBalance);

        // Transfer the shares to be burned from the user to this contract.
        TFHE.allowTransient(amount, address(indexFundToken));
        indexFundToken.transferFrom(msg.sender, address(this), amount);
        uint256 transferErrorId = indexFundToken.errorGetCounter() - 1;
        euint8 transferErrorCode = indexFundToken.getErrorCodeForTransferId(transferErrorId);

        uint256[] memory cts = new uint256[](4);
        cts[0] = Gateway.toUint256(transferErrorCode);
        cts[1] = Gateway.toUint256(amount);
        cts[2] = Gateway.toUint256(redeemIndexTokens);
        cts[3] = Gateway.toUint256(hasUserEnoughSharesToBurn);
        uint256 requestID =
            Gateway.requestDecryption(cts, this.burnSharesCallback.selector, 0, block.timestamp + 100, false);
        addParamsAddress(requestID, msg.sender);
    }

    /**
     * @notice Initiates the redemption process after burning shares.
     * @dev This function handles both index token redemption and stablecoin redemption paths.
     * For stablecoin redemption, it processes swaps and prepares the stablecoin for transfer.
     * For index token redemption, it sends the tokens back directly.
     */
    function initRedeemAfterBurn() external {
        address user = msg.sender;
        if (userToTokenWithdrawableAmounts[user].length == 0) {
            revert NoPendingWithdrawal(TFHE.asEaddress(user));
        }
        uint256[] memory tokenAmountsToRedeemOrSwap = userToTokenWithdrawableAmounts[user];
        bool redeemIndexTokens = redeemIndexTokenForPendingWithdrawal[user];
        delete userToTokenWithdrawableAmounts[user];

        if (redeemIndexTokens) {
            if (indexFundState.pendingTokenToStablecoinSwapsCounter < indexFundState.numberOfSwapsToBatch) {
                revert NotEnoughSwapsToBatch();
            }
            indexFundState.sendTokensBackOnBurn(user, tokenAmountsToRedeemOrSwap);
            emit IndexTokensRedeemed();
        } else {
            ConfidentialERC20WithErrorsWrapped stablecoin = indexFundState.stablecoin;
            uint256 stablecoinToSendBack = indexFundState.processSwapsOnBurn(tokenAmountsToRedeemOrSwap);

            ERC20 underlying = indexFundState.decryptedStablecoin;
            address wrapper = address(indexFundState.stablecoin);
            underlying.approve(wrapper, stablecoinToSendBack);
            stablecoin.wrap(stablecoinToSendBack);

            euint64 encryptedStablecoinToSendBack = TFHE.asEuint64(stablecoinToSendBack);
            userToPendingStablecoinTransfer[msg.sender] = encryptedStablecoinToSendBack;
            TFHE.allow(userToPendingStablecoinTransfer[msg.sender], msg.sender);
            TFHE.allowThis(userToPendingStablecoinTransfer[msg.sender]);
        }
    }

    /**
     * @notice Completes the stablecoin redemption process by transferring the stablecoin to the user.
     * @dev This function transfers the encrypted stablecoin amount that was prepared in initRedeemAfterBurn.
     * @param user The address of the user to receive the stablecoin
     */
    function finishRedeemInStablecoinCase(address user) public {
        euint64 encryptedStablecoinToSendBack = userToPendingStablecoinTransfer[user];
        userToPendingStablecoinTransfer[user] = TFHE.asEuint64(0);
        ConfidentialERC20WithErrorsWrapped stablecoin = getStablecoin();
        TFHE.allowTransient(encryptedStablecoinToSendBack, address(stablecoin));
        stablecoin.transfer(user, encryptedStablecoinToSendBack);
        emit BurnSwapsPerformed();
    }

    /**
     * @notice Callback function for the mint shares operation.
     * @dev This function is called by the gateway after decryption of the mint amount.
     * It handles the actual minting of shares and processing of the stablecoin deposit.
     * @param requestID The ID of the decryption request
     * @param transferErrorCode The error code from the stablecoin transfer
     * @param decryptedAmount The decrypted amount of stablecoin to mint shares for
     */
    function mintSharesCallback(uint256 requestID, uint8 transferErrorCode, uint64 decryptedAmount)
        public
        nonReentrant
        onlyGateway
    {
        address[] memory params = getParamsAddress(requestID);
        address user = params[0];
        ConfidentialERC20WithErrorsWrapped stablecoin = getStablecoin();
        uint8 noErrorCode = uint8(ConfidentialERC20WithErrors.ErrorCodes.NO_ERROR);
        if (transferErrorCode != noErrorCode) {
            revert EncryptedTransferFailed(
                TFHE.asEaddress(address(stablecoin)),
                TFHE.asEaddress(msg.sender),
                TFHE.asEaddress(address(this)),
                decryptedAmount
            );
        }
        emit EncryptedStablecoinTransfer(
            TFHE.asEaddress(user), TFHE.asEaddress(address(this)), TFHE.asEuint64(decryptedAmount)
        );
        if (decryptedAmount > indexFundState.MAX_AMOUNT_TO_MINT_OR_BURN) {
            euint64 amount = TFHE.asEuint64(decryptedAmount);
            TFHE.allowTransient(amount, address(stablecoin));
            // Refund the user the amount of stablecoin they tried to deposit
            stablecoin.transfer(user, amount);
            emit SharesToMintAmountBiggerThanMax(TFHE.asEaddress(user), decryptedAmount);
        }
        userToPendingMintAmount[user] = decryptedAmount;
    }

    /**
     * @notice Completes the mint shares process by processing the decrypted amount.
     * @dev This function handles the unwrapping of stablecoin and processing of swaps after the callback.
     * @param user The address of the user who initiated the mint
     */
    function finishMintShares(address user) public {
        uint64 decryptedAmount = userToPendingMintAmount[user];
        require(decryptedAmount > 0, "No pending mint for this user");
        userToPendingMintAmount[user] = 0;
        ConfidentialERC20WithErrorsWrapped stablecoin = getStablecoin();
        stablecoin.unwrap(decryptedAmount);
        (uint256 stablecoinIn, uint256 feeCollected) = indexFundState.preprocessSwapsOnMint(decryptedAmount);
        emit FeeCollected(TFHE.asEaddress(user), feeCollected);
        if (indexFundState.pendingStablecoinToTokenSwapsCounter == indexFundState.numberOfSwapsToBatch) {
            indexFundState.processSwapsOnMint();
            emit MintSwapsPerformed();
        }
        updateSharePrice();
        require(indexFundState.sharePrice > 0, "Share price must be greater than zero");
        uint64 sharesToMint = uint64(stablecoinIn / indexFundState.sharePrice);
        IndexFundToken(indexFundState.indexFundToken).mint(user, sharesToMint);
        emit SharesMinted(TFHE.asEaddress(user), sharesToMint);
    }

    function burnSharesCallback(
        uint256 requestID,
        uint8 transferErrorCode,
        uint64 decryptedAmount,
        bool redeemIndexTokens,
        bool hasUserEnoughSharesToBurn
    ) public nonReentrant onlyGateway {
        uint8 noErrorCode = uint8(ConfidentialERC20WithErrors.ErrorCodes.NO_ERROR);
        if (transferErrorCode != noErrorCode) {
            revert EncryptedTransferFailed(
                TFHE.asEaddress(address(indexFundState.indexFundToken)),
                TFHE.asEaddress(msg.sender),
                TFHE.asEaddress(address(this)),
                decryptedAmount
            );
        }
        if (decryptedAmount > indexFundState.MAX_AMOUNT_TO_MINT_OR_BURN) {
            revert SharesToBurnAmountBiggerThanMax(TFHE.asEaddress(msg.sender), decryptedAmount);
        }
        address[] memory params = getParamsAddress(requestID);
        address user = params[0];
        if (!hasUserEnoughSharesToBurn) {
            revert UserShareBalanceTooSmall(TFHE.asEaddress(user), decryptedAmount);
        }
        updateSharePrice();
        indexFundState.indexFundToken.burn(decryptedAmount);
        emit SharesBurned(TFHE.asEaddress(msg.sender), decryptedAmount);
        uint256[] memory tokenAmountsToRedeemOrSwap = indexFundState.computeAmountsToSwapOrRedeemOnBurn(decryptedAmount);
        userToTokenWithdrawableAmounts[user] = tokenAmountsToRedeemOrSwap;
        redeemIndexTokenForPendingWithdrawal[user] = redeemIndexTokens;
        if (!redeemIndexTokens) {
            indexFundState.pendingTokenToStablecoinSwapsCounter++;
        }
    }

    /**
     * @notice Computes the current value per share based on market data.
     */
    function updateSharePrice() public {
        uint256 totalValue = 0;
        address[] memory indexTokens = indexFundState.indexTokens;
        for (uint256 i = 0; i < indexTokens.length; i++) {
            uint256 tokenPrice = IMarketDataFetcher(indexFundState.marketDataFetcher).getTokenPrice(indexTokens[i]);
            uint256 tokenAmount = IERC20(indexTokens[i]).balanceOf(address(this));
            uint8 dec = ERC20(indexTokens[i]).decimals();
            totalValue += ((tokenPrice * tokenAmount) / (10 ** dec));
        }
        uint256 supply = indexFundState.indexFundToken.totalSupply();
        if (supply > 0) {
            indexFundState.sharePrice = (totalValue * USDC_DECIMALS) / supply;
        }
    }
    /**
     * @notice Retrieves the list of index token addresses.
     * @return An array of addresses representing the index tokens.
     */

    function getIndexTokens() public view returns (address[] memory) {
        return indexFundState.indexTokens;
    }

    /**
     * @notice Retrieves the index fund token contract instance.
     * @return The IndexFundToken contract.
     */
    function getIndexFundToken() public view returns (IndexFundToken) {
        return indexFundState.indexFundToken;
    }

    /**
     * @notice Retrieves the stablecoin contract used by the index fund.
     * @return The IERC20 stablecoin contract.
     */
    function getStablecoin() public view returns (ConfidentialERC20WithErrorsWrapped) {
        return indexFundState.stablecoin;
    }

    /**
     * @notice Retrieves the current share price
     */
    function getSharePrice() public view returns (uint256 sharePrice) {
        return indexFundState.sharePrice;
    }

    /**
     * @notice Retrieves the pending stablecoin amount for redemption for the caller.
     * @return pendingStablecoinRedeemAmount The encrypted amount of stablecoin pending for redemption
     */
    function getPendingStablecoinRedeemAmount() public view returns (euint64 pendingStablecoinRedeemAmount) {
        pendingStablecoinRedeemAmount = userToPendingStablecoinTransfer[msg.sender];
    }

    /**
     * @notice Transfers the collected fees to the protocol owner.
     * @dev Only callable by the protocol owner and protected against reentrancy.
     */
    function sendFeesToProtocolOwner() public onlyIndexFundFactoryOwner nonReentrant {
        require(indexFundState.collectedFees > 0, "No fees to send");
        // Reset fees before transferring to prevent reentrancy.
        ERC20 decryptedStablecoin = indexFundState.decryptedStablecoin;
        require(
            decryptedStablecoin.transfer(protocolOwner, indexFundState.collectedFees),
            "Failed to send fees to protocol owner."
        );
        indexFundState.collectedFees = 0;
    }
}
