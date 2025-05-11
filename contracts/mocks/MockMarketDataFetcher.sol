// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MockMarketDataFetcher {
    uint256 public fakeTotal;
    uint256[] public fakeIndiv;

    /// @notice Set the values that getIndexMarketCaps will return
    function setIndexMarketCaps(uint256 _total, uint256[] calldata _indiv) external {
        fakeTotal = _total;
        fakeIndiv = _indiv;
    }

    function getIndexMarketCaps(address[] calldata)
        external
        view
        returns (uint256 totalMarketCap, uint256[] memory individualMarketCaps)
    {
        totalMarketCap = fakeTotal;
        individualMarketCaps = fakeIndiv;
    }

    // stub, we only need getIndexMarketCaps for mint logic
    function getTokenMarketCap(address) public pure returns (uint256) {
        return 0;
    }

    function getTokenPrice(address) public pure returns (uint256) {
        return 1;
    }
}
