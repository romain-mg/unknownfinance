// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IIndexFundFactory {
    error CurrencyPairNotWhitelisted(address token, address stablecoin);

    error IndexFundAlreadyExists(address[] indexTokens, address stablecoin);

    function createIndexFund(
        address[] memory _indexTokens,
        address _stablecoin,
        bool isStablecoinEncrypted
    ) external returns (address);
}
