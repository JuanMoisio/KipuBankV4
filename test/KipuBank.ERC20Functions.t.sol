// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {KipuBank} from "../src/KipuBank.sol";
import {KipuGLD} from "../src/tokens/KipuGLD.sol";
import {MockUSDC} from "../src/tokens/MockUSDC.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {MockUniswapV2Router} from "../test/KipuBank.Native.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBank ERC20 Functions Test Suite
 * @dev Tests for ERC20 deposit, withdrawal and swap functionality
 */
contract KipuBankERC20FunctionsTest is Test {
    
    KipuBank public bank;
    KipuGLD public kgld;
    MockUSDC public usdc;
    MockV3Aggregator public priceFeed;
    MockUniswapV2Router public router;
    
    // Create a mock token for testing swaps
    MockUSDC public randomToken;
    
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public owner = address(this);
    
    uint256 constant INITIAL_ETH_PRICE = 3000e8; // $3000
    uint256 constant WITHDRAW_MAX = 1 ether;
    uint256 constant BANK_CAP = 10 ether;
    uint256 constant BANK_USD_CAP = 50000e18; // $50k
    
    // Events to test (matching the contract's event signatures)
    event erc20DepositDone(address indexed token, address indexed client, uint256 amount);
    event erc20WithdrawalDone(address indexed token, address indexed client, uint256 amount);
    
    function setUp() public {
        // Deploy all contracts
        kgld = new KipuGLD(address(this), 1_000_000e18);
        usdc = new MockUSDC(address(this));
        usdc.mint(address(this), 10_000_000e6); // 10M USDC
        
        // Create a random token for swap testing
        randomToken = new MockUSDC(address(this));
        randomToken.mint(address(this), 10_000_000e18); // 10M tokens
        
        priceFeed = new MockV3Aggregator(8, int256(INITIAL_ETH_PRICE));
        router = new MockUniswapV2Router(address(0x1234567890123456789012345678901234567890));
        
        // Deploy KipuBank
        bank = new KipuBank(
            address(this), // initialOwner
            WITHDRAW_MAX,
            BANK_CAP, 
            AggregatorV3Interface(address(priceFeed)),
            BANK_USD_CAP,
            IERC20(address(usdc)),
            IERC20(address(kgld)),
            router
        );
        
        // Setup users with tokens
        kgld.transfer(user1, 10000e18);
        kgld.transfer(user2, 10000e18);
        
        usdc.mint(user1, 10000e6); // 10k USDC
        usdc.mint(user2, 10000e6); // 10k USDC
        
        randomToken.mint(user1, 50000e18); // 50k random tokens
        randomToken.mint(user2, 50000e18);
        
        // Setup router with liquidity
        vm.deal(address(router), 100 ether);
        usdc.mint(address(router), 1_000_000_000e6); // 1B USDC to router (much higher for all tests)
        kgld.transfer(address(router), 100000e18);
        randomToken.mint(address(router), 1_000_000e18);
        
        // Users approve bank to spend their tokens
        vm.prank(user1);
        kgld.approve(address(bank), type(uint256).max);
        vm.prank(user1);
        usdc.approve(address(bank), type(uint256).max);
        vm.prank(user1);
        randomToken.approve(address(bank), type(uint256).max);
        
        vm.prank(user2);
        kgld.approve(address(bank), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(bank), type(uint256).max);
        vm.prank(user2);
        randomToken.approve(address(bank), type(uint256).max);
    }
    
    // =========================
    // DEPOSIT ERC20 - KGLD TESTS
    // =========================
    
    function test_depositERC20_KGLD_Success() public {
        uint256 amount = 1000e18;
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit erc20DepositDone(address(kgld), user1, amount);
        
        bank.depositERC20(IERC20(address(kgld)), amount);
        
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), amount);
        assertEq(kgld.balanceOf(user1), 10000e18 - amount); // User balance decreased
        assertEq(kgld.balanceOf(address(bank)), amount); // Bank received tokens
    }
    
    function test_depositERC20_KGLD_UpdatesTransactionCounter() public {
        uint256 amount = 500e18;
        (uint256 txBefore,) = bank.bankStats();
        
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), amount);
        
        (uint256 txAfter,) = bank.bankStats();
        assertEq(txAfter, txBefore + 1);
    }
    
    function test_depositERC20_KGLD_RevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert with zeroDeposit()
        bank.depositERC20(IERC20(address(kgld)), 0);
    }
    
    function test_depositERC20_KGLD_RevertsWhenPaused() public {
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger whenNotPaused modifier
        bank.depositERC20(IERC20(address(kgld)), 1000e18);
    }
    
    // =========================
    // DEPOSIT ERC20 - SWAP TESTS
    // =========================
    
    function test_depositERC20_SwapToken_Success() public {
        uint256 tokenAmount = 1000e18;
        uint256 expectedUsdcOut = 3000000e18; // 1000 tokens * 3000 rate = 3,000,000 USDC (in 18 decimals internally)
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit erc20DepositDone(address(randomToken), user1, tokenAmount);
        
        bank.depositERC20(IERC20(address(randomToken)), tokenAmount);
        
        // Should credit USDC to user (swapped from random token)
        assertEq(bank.erc20Balances(IERC20(address(usdc)), user1), expectedUsdcOut);
        
        // User's random token balance should decrease
        assertEq(randomToken.balanceOf(user1), 50000e18 - tokenAmount);
    }
    
    function test_depositERC20_SwapToken_UpdatesTransactionCounter() public {
        uint256 tokenAmount = 500e18;
        (uint256 txBefore,) = bank.bankStats();
        
        vm.prank(user1);
        bank.depositERC20(IERC20(address(randomToken)), tokenAmount);
        
        (uint256 txAfter,) = bank.bankStats();
        assertEq(txAfter, txBefore + 1);
    }
    
    function test_depositERC20_SwapToken_MultipleSwaps() public {
        uint256 amount1 = 1000e18;
        uint256 amount2 = 2000e18;
        
        // First swap
        vm.prank(user1);
        bank.depositERC20(IERC20(address(randomToken)), amount1);
        
        uint256 usdcBalance1 = bank.erc20Balances(IERC20(address(usdc)), user1);
        assertGt(usdcBalance1, 0);
        
        // Second swap
        vm.prank(user1);
        bank.depositERC20(IERC20(address(randomToken)), amount2);
        
        uint256 usdcBalance2 = bank.erc20Balances(IERC20(address(usdc)), user1);
        assertGt(usdcBalance2, usdcBalance1); // Should accumulate
    }
    
    // =========================
    // WITHDRAWAL ERC20 TESTS
    // =========================
    
    function test_withdrawalERC20_KGLD_Success() public {
        uint256 depositAmount = 2000e18;
        uint256 withdrawAmount = 1000e18;
        
        // First deposit KGLD
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), depositAmount);
        
        // Then withdraw
        uint256 balanceBefore = kgld.balanceOf(user1);
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit erc20WithdrawalDone(address(kgld), user1, withdrawAmount);
        
        bank.withdrawalERC20(IERC20(address(kgld)), withdrawAmount);
        
        uint256 balanceAfter = kgld.balanceOf(user1);
        assertEq(balanceAfter - balanceBefore, withdrawAmount);
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), depositAmount - withdrawAmount);
    }
    
    function test_withdrawalERC20_USDC_Success() public {
        uint256 swapAmount = 1000e18;
        uint256 expectedUsdcOut = 3000000e18; // 1000 tokens * 3000 rate = 3,000,000 USDC (in 18 decimals internally)
        
        // Deposit random token (gets swapped to USDC)
        vm.prank(user1);
        bank.depositERC20(IERC20(address(randomToken)), swapAmount);
        
        // Withdraw USDC
        uint256 balanceBefore = usdc.balanceOf(user1);
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit erc20WithdrawalDone(address(usdc), user1, expectedUsdcOut);
        
        bank.withdrawalERC20(IERC20(address(usdc)), expectedUsdcOut);
        
        uint256 balanceAfter = usdc.balanceOf(user1);
        // User receives USDC in native 6 decimals, so divide internal 18 decimals by 1e12
        assertEq(balanceAfter - balanceBefore, expectedUsdcOut / 1e12);
        assertEq(bank.erc20Balances(IERC20(address(usdc)), user1), 0);
    }
    
    function test_withdrawalERC20_UpdatesWithdrawalCounter() public {
        uint256 amount = 1000e18;
        
        // Setup: deposit first
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), amount);
        
        (,uint256 withdrawalsBefore) = bank.bankStats();
        
        // Withdraw
        vm.prank(user1);
        bank.withdrawalERC20(IERC20(address(kgld)), amount);
        
        (,uint256 withdrawalsAfter) = bank.bankStats();
        assertEq(withdrawalsAfter, withdrawalsBefore + 1);
    }
    
    function test_withdrawalERC20_RevertsInsufficientFunds() public {
        uint256 depositAmount = 500e18;
        uint256 withdrawAmount = 1000e18; // More than deposited
        
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), depositAmount);
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger hasFundsERC20 modifier
        bank.withdrawalERC20(IERC20(address(kgld)), withdrawAmount);
    }
    
    function test_withdrawalERC20_RevertsWhenPaused() public {
        uint256 amount = 1000e18;
        
        // Setup
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), amount);
        
        // Pause
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger whenNotPaused modifier
        bank.withdrawalERC20(IERC20(address(kgld)), amount);
    }
    
    // =========================
    // SWAP FUNCTION TESTS
    // =========================
    
    function test_swapFunction_WorksWithDifferentTokens() public {
        // Test that different tokens can be swapped
        MockUSDC[] memory tokens = new MockUSDC[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            tokens[i] = new MockUSDC(address(this));
            tokens[i].mint(user1, 10000e18);
            tokens[i].mint(address(router), 1000000e18); // Add to router
            
            vm.prank(user1);
            tokens[i].approve(address(bank), type(uint256).max);
            
            // Test deposit (which triggers swap)
            vm.prank(user1);
            bank.depositERC20(IERC20(address(tokens[i])), 1000e18);
            
            // Should have USDC balance
            assertGt(bank.erc20Balances(IERC20(address(usdc)), user1), 0);
        }
    }
    
    function test_swapFunction_HandlesDifferentAmounts() public {
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 100e18;
        amounts[1] = 500e18;
        amounts[2] = 1000e18;
        amounts[3] = 2500e18;
        
        for (uint256 i = 0; i < amounts.length; i++) {
            MockUSDC token = new MockUSDC(address(this));
            token.mint(user1, 10000e18);
            token.mint(address(router), 50000000e18); // Increased from 1M to 50M
            // Ensure main USDC also has enough balance for swaps
            usdc.mint(address(router), 50000000e6);
            
            vm.prank(user1);
            token.approve(address(bank), type(uint256).max);
            
            uint256 usdcBefore = bank.erc20Balances(IERC20(address(usdc)), user1);
            
            vm.prank(user1);
            bank.depositERC20(IERC20(address(token)), amounts[i]);
            
            uint256 usdcAfter = bank.erc20Balances(IERC20(address(usdc)), user1);
            assertGt(usdcAfter, usdcBefore); // Should increase USDC balance
        }
    }
    
    // =========================
    // INTEGRATION TESTS
    // =========================
    
    function test_fullCycle_KGLDDepositWithdraw() public {
        uint256 amount = 1500e18;
        
        vm.startPrank(user1);
        
        uint256 initialBalance = kgld.balanceOf(user1);
        
        // Deposit KGLD
        bank.depositERC20(IERC20(address(kgld)), amount);
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), amount);
        
        // Withdraw KGLD
        bank.withdrawalERC20(IERC20(address(kgld)), amount);
        
        vm.stopPrank();
        
        // Should be back to original balance
        assertEq(kgld.balanceOf(user1), initialBalance);
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), 0);
    }
    
    function test_fullCycle_TokenSwapAndUSDCWithdraw() public {
        uint256 tokenAmount = 2000e18;
        
        vm.startPrank(user1);
        
        // Deposit random token (gets swapped to USDC)
        bank.depositERC20(IERC20(address(randomToken)), tokenAmount);
        
        uint256 usdcBalance = bank.erc20Balances(IERC20(address(usdc)), user1);
        assertGt(usdcBalance, 0);
        
        // Withdraw all USDC
        bank.withdrawalERC20(IERC20(address(usdc)), usdcBalance);
        
        vm.stopPrank();
        
        // Should have withdrawn USDC and have no balance in bank
        assertEq(bank.erc20Balances(IERC20(address(usdc)), user1), 0);
        assertGt(usdc.balanceOf(user1), 10000e6); // Initial + swapped
    }
    
    function test_multipleUsersERC20Operations() public {
        uint256 kgldAmount = 1000e18;
        uint256 tokenAmount = 1500e18;
        
        // User1: Deposit KGLD
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), kgldAmount);
        
        // User2: Deposit random token (swap to USDC)
        vm.prank(user2);
        bank.depositERC20(IERC20(address(randomToken)), tokenAmount);
        
        // Check balances
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), kgldAmount);
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user2), 0);
        
        assertEq(bank.erc20Balances(IERC20(address(usdc)), user1), 0);
        assertGt(bank.erc20Balances(IERC20(address(usdc)), user2), 0);
        
        // Check transaction counter
        (uint256 deposits,) = bank.bankStats();
        assertEq(deposits, 2);
        
        // Both users withdraw
        vm.prank(user1);
        bank.withdrawalERC20(IERC20(address(kgld)), kgldAmount);
        
        uint256 user2UsdcBalance = bank.erc20Balances(IERC20(address(usdc)), user2);
        vm.prank(user2);
        bank.withdrawalERC20(IERC20(address(usdc)), user2UsdcBalance);
        
        // Check final state
        (,uint256 withdrawals) = bank.bankStats();
        assertEq(withdrawals, 2);
    }
    
    // =========================
    // FUZZ TESTS
    // =========================
    
    function testFuzz_depositERC20_KGLD(uint256 amount) public {
        amount = bound(amount, 1e18, 5000e18); // Reasonable bounds
        
        // Ensure user has enough tokens
        if (kgld.balanceOf(user1) < amount) {
            kgld.transfer(user1, amount);
        }
        
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), amount);
        
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), amount);
    }
    
    function testFuzz_depositWithdrawERC20_KGLD(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 100e18, 5000e18);
        withdrawAmount = bound(withdrawAmount, 1e18, depositAmount);
        
        // Ensure user has enough tokens
        if (kgld.balanceOf(user1) < depositAmount) {
            kgld.transfer(user1, depositAmount);
        }
        
        vm.startPrank(user1);
        
        // Deposit
        bank.depositERC20(IERC20(address(kgld)), depositAmount);
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), depositAmount);
        
        // Withdraw
        uint256 balanceBefore = kgld.balanceOf(user1);
        bank.withdrawalERC20(IERC20(address(kgld)), withdrawAmount);
        
        vm.stopPrank();
        
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), depositAmount - withdrawAmount);
        assertEq(kgld.balanceOf(user1) - balanceBefore, withdrawAmount);
    }
    
    function testFuzz_swapDeposit(uint256 amount) public {
        amount = bound(amount, 100e18, 5000e18); // Reduced upper bound to prevent router exhaustion
        
        // Create new token for each test
        MockUSDC token = new MockUSDC(address(this));
        token.mint(user1, amount * 2);
        token.mint(address(router), 100000000e18); // Increased to 100M USDC
        // Ensure main USDC has sufficient balance for swaps
        usdc.mint(address(router), 100000000e6); // Add 100M main USDC too
        
        vm.prank(user1);
        token.approve(address(bank), type(uint256).max);
        
        uint256 usdcBefore = bank.erc20Balances(IERC20(address(usdc)), user1);
        
        vm.prank(user1);
        bank.depositERC20(IERC20(address(token)), amount);
        
        uint256 usdcAfter = bank.erc20Balances(IERC20(address(usdc)), user1);
        assertGt(usdcAfter, usdcBefore); // Should have more USDC after swap
    }
}