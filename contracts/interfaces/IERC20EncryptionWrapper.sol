// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {euint256} from "fhevm/lib/TFHE.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IERC20EncryptionWrapper {
    function depositFor(address account, euint256 value) external returns (bool);

    function withdrawTo(address account, euint256 value) external returns (bool);

    function underlying() external view returns (IERC20);
}
