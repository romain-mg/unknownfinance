// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { SwapsManager } from "../swaps/SwapsManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { UniversalRouter } from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import { PoolKey, Currency } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { CurrencyLibrary } from "@uniswap/v4-core/src/types/Currency.sol";

contract SwapsManagerTest is Test {
    SwapsManager public swapsManager;
    UniversalRouter public universalRouter;
    IPermit2 public permit2;
    IERC20 public usdc;
    IERC20 public mockWbtc;
    IERC20 public uni;

    address public user = 0x98cC8F6627688A48D2A4cc17Cd79741cC67c9DdA;
    address public constant USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia USDC
    address public constant MOCK_WBTC_ADDRESS = 0x6D43d3E34D88FCBb16E906F5ED0069271b12877c; // Sepolia Mock WBTC
    address public constant UNI_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // Sepolia UNI
    address public constant UNIVERSAL_ROUTER = 0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b; // Sepolia Universal Router
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Sepolia Permit2
    address public constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;

    function setUp() public {
        // Fork Sepolia
        vm.createSelectFork(vm.envString("SEPOLIA_RPC_URL"));

        // Deploy SwapsManager
        swapsManager = new SwapsManager();
        swapsManager.initialize(UNIVERSAL_ROUTER, PERMIT2);

        // Get contract instances
        universalRouter = UniversalRouter(payable(UNIVERSAL_ROUTER));
        permit2 = IPermit2(PERMIT2);
        usdc = IERC20(USDC_ADDRESS);
        mockWbtc = IERC20(MOCK_WBTC_ADDRESS);
        uni = IERC20(UNI_ADDRESS);

        vm.deal(user, 10 ether);
        vm.deal(address(swapsManager), 0.001 ether);
        vm.deal(UNIVERSAL_ROUTER, 10 ether);
    }

    function testSwapETHForUSDC_HappyPath() public {
        // Start impersonating user
        vm.startPrank(user);

        // Record initial balances
        uint256 initialEthBalance = user.balance;
        uint256 initialUsdcBalance = usdc.balanceOf(user);

        // Execute swap
        PoolKey memory key = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(USDC_ADDRESS),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        uint128 amountIn = 1 ether;
        uint128 minAmountOut = 0; // For testing purposes, we accept any amount of USDC
        uint256 deadline = block.timestamp + 15 minutes;
        bool stablecoinForToken = false;

        swapsManager.swap{ value: amountIn }(key, amountIn, minAmountOut, deadline, stablecoinForToken, USDC_ADDRESS);

        // Record final balances
        uint256 finalEthBalance = user.balance;
        uint256 finalUsdcBalance = usdc.balanceOf(user);

        // Verify balances
        assertGt(finalUsdcBalance, initialUsdcBalance, "USDC balance should increase");
        assertEq(finalEthBalance, initialEthBalance - amountIn, "ETH balance should decrease by amountIn");
        assertEq(usdc.balanceOf(address(swapsManager)), 0, "SwapsManager should have no leftover USDC");

        vm.stopPrank();
    }

    function testSwapUSDCForMockWbtcToken_HappyPath() public {
        // Start impersonating user
        vm.startPrank(user);

        // Record initial balances
        uint256 initialUsdcBalance = usdc.balanceOf(user);
        uint256 initialMockWbtcBalance = mockWbtc.balanceOf(user);

        // Execute swap
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(USDC_ADDRESS),
            currency1: Currency.wrap(MOCK_WBTC_ADDRESS),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        uint128 amountIn = 10 * 10 ** 6; // 1000 USDC (6 decimals)
        uint128 minAmountOut = 0; // For testing purposes, we accept any amount of TestnetToken
        uint256 deadline = block.timestamp + 15 minutes;
        bool stablecoinForToken = true;

        // Approve and transfer USDC spending
        swapsManager.approveTokenWithPermit2(USDC_ADDRESS, amountIn, uint48(deadline));
        usdc.transfer(address(swapsManager), amountIn);
        swapsManager.swap(key, amountIn, minAmountOut, deadline, stablecoinForToken, USDC_ADDRESS);

        // Record final balances
        uint256 finalUsdcBalance = usdc.balanceOf(user);
        uint256 finalMockWbtcBalance = mockWbtc.balanceOf(user);

        // Verify balances
        assertGt(finalMockWbtcBalance, initialMockWbtcBalance, "Mock WBTC balance should increase");
        assertEq(finalUsdcBalance, initialUsdcBalance - amountIn, "USDC balance should decrease by amountIn");
        assertEq(mockWbtc.balanceOf(address(swapsManager)), 0, "SwapsManager should have no leftover Mock WBTC");

        vm.stopPrank();
    }

    function testSwapUSDCForUNI_HappyPath() public {
        // Start impersonating user
        vm.startPrank(user);

        // Record initial balances
        uint256 initialUsdcBalance = usdc.balanceOf(user);
        uint256 initialUniBalance = uni.balanceOf(user);

        // Execute swap
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(USDC_ADDRESS),
            currency1: Currency.wrap(UNI_ADDRESS),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        uint128 amountIn = 10 * 10 ** 6; // 10 USDC (6 decimals)
        uint128 minAmountOut = 0; // For testing purposes, we accept any amount of UNI
        uint256 deadline = block.timestamp + 15 minutes;
        bool stablecoinForToken = true;

        swapsManager.approveTokenWithPermit2(USDC_ADDRESS, amountIn, uint48(deadline));
        usdc.transfer(address(swapsManager), amountIn);
        swapsManager.swap(key, amountIn, minAmountOut, deadline, stablecoinForToken, USDC_ADDRESS);

        // Record final balances
        uint256 finalUsdcBalance = usdc.balanceOf(user);
        uint256 finalUniBalance = uni.balanceOf(user);

        // Verify balances
        assertGt(finalUniBalance, initialUniBalance, "UNI balance should increase");
        assertEq(finalUsdcBalance, initialUsdcBalance - amountIn, "USDC balance should decrease by amountIn");
        assertEq(uni.balanceOf(address(swapsManager)), 0, "SwapsManager should have no leftover UNI");

        vm.stopPrank();
    }
}
