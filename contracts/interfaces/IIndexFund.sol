// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../IndexFundToken.sol";
import {einput} from "fhevm/lib/TFHE.sol";
import {ConfidentialERC20Wrapped} from "@httpz-contracts/token/ERC20/ConfidentialERC20Wrapped.sol";

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
}
