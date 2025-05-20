// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../IndexFundToken.sol";
import {einput} from "fhevm/lib/TFHE.sol";
import {ConfidentialERC20Wrapped} from "@httpz-contracts/token/ERC20/ConfidentialERC20Wrapped.sol";
import {euint64, eaddress} from "fhevm/lib/TFHE.sol";

interface IIndexFund {
    error InsufficientAllowance(eaddress allower, address token);

    error SharesToBurnAmountBiggerThanMax(eaddress burner, uint256 amountToBurn);

    error AmountToSwapTooBig(uint256 amountToSwap);

    error EncryptedTransferFailed(eaddress token, eaddress from, eaddress to, uint256 amount);

    error TransferFailed(address token, eaddress from, eaddress to, euint256 amount);

    error UserShareBalanceTooSmall(eaddress user, uint256 amountToBurn);

    error NoPendingWithdrawal(eaddress user);

    error NotEnoughSwapsToBatch();

    event FeeCollected(eaddress user, uint256 indexed feeAmount);

    event SharesMinted(eaddress indexed user, uint256 indexed amount);

    event SharesToMintAmountBiggerThanMax(eaddress minter, uint256 amountToBurn);

    event SharesBurned(eaddress indexed user, uint256 indexed amount);

    event MintSwapsPerformed();

    event BurnSwapsPerformed();

    event IndexTokensRedeemed();

    event EncryptedStablecoinTransfer(eaddress indexed from, eaddress indexed to, euint64 indexed amount);

    event SharesMintRevertedAmountTooBig();
}
