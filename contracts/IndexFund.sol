// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

contract IndexFund {
    address[] indexTokens;

    address passiveIndexToken;

    address stablecoin;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(address indexed user, uint256 indexed amount, uint256 indexed stablecoinIn);

    event SharesBurned(address indexed user, uint256 indexed amount);

    constructor(address[] memory _indexTokens, address _passiveIndexToken, address _stablecoin) {
        indexTokens = _indexTokens;
        passiveIndexToken = _passiveIndexToken;
        stablecoin = _stablecoin;
    }

    function mintShares(uint256 amount) public {}

    function burnShares(uint256 amount) public {}

    function getIndexTokens() public view returns (address[] memory) {
        return indexTokens;
    }

    function getPassiveIndexToken() public view returns (address) {
        return passiveIndexToken;
    }

    function getStablecoin() public view returns (address) {
        return stablecoin;
    }
}
