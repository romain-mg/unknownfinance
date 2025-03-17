// SPDX-License-Identifier: MIT
pragma solidity =0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";

contract IndexFund {
    address[] indexTokens;

    address IndexFundToken;

    address stablecoin;

    event FeeCollected(address indexed user, uint256 indexed feeAmount);

    event SharesMinted(address indexed user, uint256 indexed amount, uint256 indexed stablecoinIn);

    event SharesBurned(address indexed user, uint256 indexed amount);

    constructor(address[] memory _indexTokens, address _IndexFundToken, address _stablecoin) {
        indexTokens = _indexTokens;
        IndexFundToken = _IndexFundToken;
        stablecoin = _stablecoin;
    }

    function mintShares(uint256 amount) public {}

    function burnShares(uint256 amount) public {}

    function getIndexTokens() public view returns (address[] memory) {
        return indexTokens;
    }

    function getIndexFundToken() public view returns (address) {
        return IndexFundToken;
    }

    function getStablecoin() public view returns (address) {
        return stablecoin;
    }
}
