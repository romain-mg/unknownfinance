// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "../contracts/encryption/ConfidentialERC20Wrapper.sol";
import "fhevm/lib/TFHE.sol";
import "../contracts/PassiveIndexToken.sol";
contract TestERC20 is ERC20, ERC20Permit {
    constructor(string memory name, string memory ticker) ERC20(name, ticker) ERC20Permit(name) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
contract ConfidentialERC20WrapperTest is Test {
    TestERC20 testErc20;
    ConfidentialERC20Wrapper wrappedTestErc20;
    PassiveIndexToken testPassiveIndexToken;

    function setUp() public {
        testErc20 = new TestERC20("test-erc20", "TERC20");
        testErc20.mint(address(this), 1000);
        wrappedTestErc20 = new ConfidentialERC20Wrapper("wrapped-test-erc20", "WTERC20", testErc20);
        testPassiveIndexToken = new PassiveIndexToken("test-passive-index-token", "TPIT");
    }

    function testMint() public {
        testPassiveIndexToken.mint(address(this), uint64(1000));
    }

    // function testWrap() public {
    //     testErc20.approve(address(wrappedTestErc20), 5000);
    //     wrappedTestErc20.depositFor(address(this), 500);
    // }
}
