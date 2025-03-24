// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../IndexFundToken.sol";

interface IIndexFund {
    error InsufficientAllowance(address token);

    error SharesToMintAmountTooBig(uint256 amountToMint);

    error AmountToSwapTooBig(uint256 amountToSwap);

    function mintShares(uint256 amount) external;

    function burnShares(uint256 amount) external;

    function getIndexTokens() external view returns (address[] memory);

    function getIndexFundToken() external view returns (IndexFundToken indexFundToken);

    function getStablecoin() external view returns (IERC20 stablecoin);
}
