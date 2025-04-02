// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IConfidentialERC20 } from "./IConfidentialERC20.sol";

interface IERC20EncryptionWrapper is IConfidentialERC20 {
    function depositFor(address account, uint256 value) external returns (bool);

    function withdrawTo(address account, uint256 value) external returns (bool);

    function underlying() external view returns (address);
}
