// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../IndexFundToken.sol";
import {einput} from "fhevm/lib/TFHE.sol";
import {ERC20EncryptionWrapper} from "../ERC20Encryption/ERC20EncryptionWrapper.sol";

interface IIndexFund {
    error InsufficientAllowance(address token);

    error SharesToMintAmountTooBig(uint256 amountToMint);

    error SharesToBurnAmountTooBig(uint256 amountToBurn);

    error AmountToSwapTooBig(uint256 amountToSwap);

    error TransferFailed();

    error NotEnoughSharesToBurn(address user, uint256 amountToBurn);

    event FeeCollected(uint256 indexed feeAmount);

    event SharesMinted(address indexed user, uint256 indexed amount);

    event SharesBurned(address indexed user, uint256 indexed amount);

    event MintSwapsPerformed();

    event BurnSwapsPerformed();

    event IndexTokensRedeemed();

    function mintShares(einput encryptedAmount, bytes calldata inputProof) external;

    function burnShares(einput encryptedAmount, einput encryptedRedeemIndexTokens, bytes calldata inputProof)
        external;

    function getIndexTokens() external view returns (address[] memory);

    function getIndexFundToken() external view returns (IndexFundToken indexFundToken);

    function getStablecoin() external view returns (ERC20EncryptionWrapper stablecoin);
}
