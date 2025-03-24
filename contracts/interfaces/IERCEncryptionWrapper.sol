// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IERCEncryptionWrapper {
    function depositFor(address account, uint256 value) external returns (bool);

    function withdrawTo(address account, uint256 value) external returns (bool);

    function underlying() external view returns (address);
}
