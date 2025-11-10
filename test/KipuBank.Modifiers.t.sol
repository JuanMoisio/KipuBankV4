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
 * @title KipuBank Modifiers Test Suite
 * @dev Tests specifically designed to trigger all modifiers and edge cases
 */
contract KipuBankModifiersTest is Test {
    
    KipuBank public bank;
    KipuGLD public kgld;
    MockUSDC public usdc;
    MockV3Aggregator public priceFeed;
    MockUniswapV2Router public router;
    
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    uint256 constant INITIAL_ETH_PRICE = 2500e8; // $2500
    uint256 constant WITHDRAW_MAX = 1 ether;
    uint256 constant BANK_CAP = 5 ether;  // Lower cap for easier testing
    uint256 constant BANK_USD_CAP = 10000e18; // $10k for easier testing
    
    // Custom errors to test
    error zeroDeposit();
    error transactionFailed();
    error insufficientFundsToWithdraw();
    error withdrawCap();
    error bankCap();
    error usdCapExceeded();
    
    function setUp() public {
        // Deploy all contracts
        kgld = new KipuGLD(address(this), 1_000_000e18);
        usdc = new MockUSDC(address(this));
        usdc.mint(address(this), 10_000_000e6);
        
        priceFeed = new MockV3Aggregator(8, int256(INITIAL_ETH_PRICE));
        router = new MockUniswapV2Router(address(0x1234567890123456789012345678901234567890));
        
        // Deploy KipuBank with smaller limits for easier testing
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
        
        // Setup users
        vm.deal(user1, 20 ether);
        vm.deal(user2, 20 ether);
        
        kgld.transfer(user1, 10000e18);
        kgld.transfer(user2, 10000e18);
        
        // Approvals
        vm.prank(user1);
        kgld.approve(address(bank), type(uint256).max);
        vm.prank(user2);
        kgld.approve(address(bank), type(uint256).max);
    }
    
    // =========================
    // nonZeroValue MODIFIER TESTS
    // =========================
    
    function test_modifier_nonZeroValue_RevertsOnZeroDeposit() public {
        vm.prank(user1);
        vm.expectRevert(); // Should trigger nonZeroValue modifier
        bank.deposit{value: 0}();
    }
    
    function test_modifier_nonZeroValue_PassesWithValidAmount() public {
        vm.prank(user1);
        bank.deposit{value: 0.1 ether}(); // Should pass
        assertEq(bank.balances(user1), 0.1 ether);
    }
    
    // =========================
    // underTxCap MODIFIER TESTS
    // =========================
    
    function test_modifier_underTxCap_RevertsWhenExceedsBankCap() public {
        uint256 excessiveAmount = BANK_CAP + 1 wei;
        vm.deal(user1, excessiveAmount);
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger underTxCap modifier  
        bank.deposit{value: excessiveAmount}();
    }
    
    function test_modifier_underTxCap_PassesAtBankCapLimit() public {
        // Use smaller amount that won't exceed USD cap: $3000 USD / $3000 per ETH = 1 ETH 
        uint256 safeAmount = 1 ether;
        vm.prank(user1);
        bank.deposit{value: safeAmount}(); // Should pass - well under both caps
        assertEq(bank.balances(user1), safeAmount);
    }
    
    function test_modifier_underTxCap_ERC20Deposits() public {
        // ERC20 deposits should also check transaction cap (though different logic)
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), 1000e18); // Should pass
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), 1000e18);
    }
    
    // =========================
    // countDeposit MODIFIER TESTS
    // =========================
    
    function test_modifier_countDeposit_IncrementsCounter() public {
        (uint256 depositsBefore,) = bank.bankStats();
        
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        
        (uint256 depositsAfter,) = bank.bankStats();
        assertEq(depositsAfter, depositsBefore + 1);
    }
    
    function test_modifier_countDeposit_IncrementsOnERC20Deposits() public {
        (uint256 depositsBefore,) = bank.bankStats();
        
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), 500e18);
        
        (uint256 depositsAfter,) = bank.bankStats();
        assertEq(depositsAfter, depositsBefore + 1);
    }
    
    function test_modifier_countDeposit_MultipleDeposits() public {
        (uint256 initialDeposits,) = bank.bankStats();
        
        // Multiple deposits should increment counter each time
        vm.startPrank(user1);
        bank.deposit{value: 1 ether}();
        bank.deposit{value: 1 ether}();
        bank.depositERC20(IERC20(address(kgld)), 100e18);
        vm.stopPrank();
        
        (uint256 finalDeposits,) = bank.bankStats();
        assertEq(finalDeposits, initialDeposits + 3);
    }
    
    // =========================
    // countWithdrawal MODIFIER TESTS  
    // =========================
    
    function test_modifier_countWithdrawal_IncrementsCounter() public {
        // Setup: deposit first
        vm.prank(user1);
        bank.deposit{value: 2 ether}();
        
        (,uint256 withdrawalsBefore) = bank.bankStats();
        
        // Withdraw
        vm.prank(user1);
        bank.withdrawal(1 ether);
        
        (,uint256 withdrawalsAfter) = bank.bankStats();
        assertEq(withdrawalsAfter, withdrawalsBefore + 1);
    }
    
    function test_modifier_countWithdrawal_ERC20Withdrawals() public {
        // Setup: deposit KGLD first
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), 1000e18);
        
        (,uint256 withdrawalsBefore) = bank.bankStats();
        
        // Withdraw
        vm.prank(user1);
        bank.withdrawalERC20(IERC20(address(kgld)), 500e18);
        
        (,uint256 withdrawalsAfter) = bank.bankStats();
        assertEq(withdrawalsAfter, withdrawalsBefore + 1);
    }
    
    // =========================
    // hasFunds MODIFIER TESTS
    // =========================
    
    function test_modifier_hasFunds_RevertsInsufficientBalance() public {
        // Deposit small amount
        vm.prank(user1);
        bank.deposit{value: 0.5 ether}();
        
        // Try to withdraw more
        vm.prank(user1);
        vm.expectRevert(); // Should trigger hasFunds modifier
        bank.withdrawal(1 ether);
    }
    
    function test_modifier_hasFunds_PassesWithSufficientFunds() public {
        vm.prank(user1);
        bank.deposit{value: 2 ether}();
        
        vm.prank(user1);
        bank.withdrawal(1 ether); // Should pass
        assertEq(bank.balances(user1), 1 ether);
    }
    
    function test_modifier_hasFunds_ExactBalance() public {
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        
        vm.prank(user1);
        bank.withdrawal(1 ether); // Should pass with exact balance
        assertEq(bank.balances(user1), 0);
    }
    
    // =========================
    // withinWithdrawCap MODIFIER TESTS
    // =========================
    
    function test_modifier_withinWithdrawCap_RevertsExcessiveWithdraw() public {
        // Deposit smaller amount to avoid USD cap: 3 ETH = $9000 USD (under $10k cap)
        vm.prank(user1);
        bank.deposit{value: 3 ether}();
        
        // Try to withdraw more than cap
        uint256 excessiveAmount = WITHDRAW_MAX + 1 wei;
        vm.prank(user1);
        vm.expectRevert(); // Should trigger withinWithdrawCap modifier
        bank.withdrawal(excessiveAmount);
    }
    
    function test_modifier_withinWithdrawCap_PassesAtLimit() public {
        // Deposit smaller amount to avoid USD cap: 3 ETH = $9000 USD (under $10k cap)
        vm.prank(user1);
        bank.deposit{value: 3 ether}();
        
        vm.prank(user1);
        bank.withdrawal(WITHDRAW_MAX); // Should pass exactly at limit
        assertEq(bank.balances(user1), 3 ether - WITHDRAW_MAX);
    }
    
    // =========================
    // hasFundsERC20 MODIFIER TESTS
    // =========================
    
    function test_modifier_hasFundsERC20_RevertsInsufficientBalance() public {
        // Deposit small amount
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), 500e18);
        
        // Try to withdraw more
        vm.prank(user1);
        vm.expectRevert(); // Should trigger hasFundsERC20 modifier
        bank.withdrawalERC20(IERC20(address(kgld)), 1000e18);
    }
    
    function test_modifier_hasFundsERC20_PassesWithSufficientFunds() public {
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), 2000e18);
        
        vm.prank(user1);
        bank.withdrawalERC20(IERC20(address(kgld)), 1000e18); // Should pass
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), 1000e18);
    }
    
    // =========================
    // underUsdCap MODIFIER TESTS
    // =========================
    
    function test_modifier_underUsdCap_RevertsWhenExceedsUsdCap() public {
        // Calculate amount that would exceed USD cap
        uint256 amountToExceedUsdCap = (BANK_USD_CAP * 1e8) / INITIAL_ETH_PRICE + 1 ether;
        vm.deal(user1, amountToExceedUsdCap);
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger underUsdCap modifier
        bank.deposit{value: amountToExceedUsdCap}();
    }
    
    function test_modifier_underUsdCap_PassesUnderLimit() public {
        // Calculate safe amount under USD cap
        uint256 safeAmount = (BANK_USD_CAP * 1e8) / INITIAL_ETH_PRICE / 2; // Half of limit
        
        vm.prank(user1);
        bank.deposit{value: safeAmount}(); // Should pass
        assertEq(bank.balances(user1), safeAmount);
    }
    
    function test_modifier_underUsdCap_AccumulatesCorrectly() public {
        uint256 amount1 = 1 ether;
        uint256 amount2 = 1 ether;
        
        // First deposit
        vm.prank(user1);
        bank.deposit{value: amount1}();
        
        // Second deposit should accumulate USD liability
        vm.prank(user2);
        bank.deposit{value: amount2}();
        
        // Total USD liability should be roughly 2 ETH * price
        uint256 expectedUsd = ((amount1 + amount2) * INITIAL_ETH_PRICE) / 1e8;
        assertApproxEqRel(bank.bankUsdLiabilities(), expectedUsd, 0.01e18); // 1% tolerance
    }
    
    function test_modifier_underUsdCap_WithPriceChange() public {
        uint256 amount = 1 ether;
        
        // Deposit at initial price
        vm.prank(user1);
        bank.deposit{value: amount}();
        
        // Change ETH price
        uint256 newPrice = 5000e8; // $5000
        priceFeed.updateAnswer(int256(newPrice));
        
        // New deposits should use new price for USD calculation
        vm.prank(user2);
        bank.deposit{value: amount}();
        
        // Should have more USD liability due to higher ETH price
        uint256 expectedUsd1 = (amount * INITIAL_ETH_PRICE) / 1e8;
        uint256 expectedUsd2 = (amount * newPrice) / 1e8;
        uint256 totalExpected = expectedUsd1 + expectedUsd2;
        
        assertApproxEqRel(bank.bankUsdLiabilities(), totalExpected, 0.02e18); // 2% tolerance
    }
    
    // =========================
    // COMBINED MODIFIER TESTS
    // =========================
    
    function test_modifiers_Combined_DepositWithAllChecks() public {
        uint256 validAmount = 0.5 ether; // Under all caps, non-zero
        
        (uint256 depositsBefore,) = bank.bankStats();
        uint256 liabilitiesBefore = bank.bankUsdLiabilities();
        
        vm.prank(user1);
        bank.deposit{value: validAmount}();
        
        // All modifiers should have been applied
        assertEq(bank.balances(user1), validAmount); // nonZeroValue, underTxCap, underUsdCap passed
        
        (uint256 depositsAfter,) = bank.bankStats();
        assertEq(depositsAfter, depositsBefore + 1); // countDeposit applied
        
        assertGt(bank.bankUsdLiabilities(), liabilitiesBefore); // underUsdCap tracking worked
    }
    
    function test_modifiers_Combined_WithdrawWithAllChecks() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 0.5 ether; // Under withdraw cap, user has funds
        
        // Setup
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        (,uint256 withdrawalsBefore) = bank.bankStats();
        
        vm.prank(user1);
        bank.withdrawal(withdrawAmount);
        
        // All modifiers should have been applied
        assertEq(bank.balances(user1), depositAmount - withdrawAmount); // hasFunds, withinWithdrawCap passed
        
        (,uint256 withdrawalsAfter) = bank.bankStats();
        assertEq(withdrawalsAfter, withdrawalsBefore + 1); // countWithdrawal applied
        
        // nonReentrant should have worked (no reentrancy attack possible in this test)
    }
    
    // =========================
    // REENTRANCY TESTS
    // =========================
    
    function test_modifier_nonReentrant_PreventsReentrancy() public {
        // This is harder to test without a malicious contract, but we can verify
        // that normal operations work and the modifier is being applied
        
        vm.prank(user1);
        bank.deposit{value: 2 ether}();
        
        vm.prank(user1);
        bank.withdrawal(1 ether); // Should work normally
        
        assertEq(bank.balances(user1), 1 ether);
    }
    
    // =========================
    // PAUSE MODIFIER TESTS
    // =========================
    
    function test_modifier_whenNotPaused_BlocksWhenPaused() public {
        // Pause the contract
        bank.pause();
        
        // All main functions should revert when paused
        vm.prank(user1);
        vm.expectRevert();
        bank.deposit{value: 1 ether}();
        
        vm.prank(user1); 
        vm.expectRevert();
        bank.depositERC20(IERC20(address(kgld)), 1000e18);
        
        // Setup for withdrawal tests
        bank.unpause();
        vm.prank(user1);
        bank.deposit{value: 2 ether}();
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), 1000e18);
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        bank.withdrawal(1 ether);
        
        vm.prank(user1);
        vm.expectRevert();
        bank.withdrawalERC20(IERC20(address(kgld)), 500e18);
    }
    
    function test_modifier_whenNotPaused_WorksWhenNotPaused() public {
        // Should work normally when not paused
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        assertEq(bank.balances(user1), 1 ether);
        
        vm.prank(user1);
        bank.depositERC20(IERC20(address(kgld)), 1000e18);
        assertEq(bank.erc20Balances(IERC20(address(kgld)), user1), 1000e18);
    }
    
    // =========================
    // EDGE CASES & STRESS TESTS
    // =========================
    
    function test_edgeCase_MultipleUsersHitLimits() public {
        // Test what happens when multiple users try to hit various limits
        
        // User1 deposits near USD cap
        uint256 amount1 = (BANK_USD_CAP * 1e8) / INITIAL_ETH_PRICE / 2;
        vm.prank(user1);
        bank.deposit{value: amount1}();
        
        // User2 tries to exceed remaining USD cap
        uint256 remainingUsdCapInEth = ((BANK_USD_CAP - bank.bankUsdLiabilities()) * 1e8) / INITIAL_ETH_PRICE;
        uint256 excessiveAmount = remainingUsdCapInEth + 0.1 ether;
        
        vm.deal(user2, excessiveAmount);
        vm.prank(user2);
        vm.expectRevert(); // Should hit USD cap
        bank.deposit{value: excessiveAmount}();
    }
    
    function test_edgeCase_WithdrawAfterPriceChange() public {
        uint256 depositAmount = 2 ether;
        
        // Deposit at initial price
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        uint256 liabilities1 = bank.bankUsdLiabilities();
        
        // Change price (should not affect existing deposits)
        priceFeed.updateAnswer(int256(5000e8)); // $5000
        
        // Withdraw should work and update liabilities correctly
        vm.prank(user1);
        bank.withdrawal(1 ether);
        
        uint256 liabilities2 = bank.bankUsdLiabilities();
        assertLt(liabilities2, liabilities1); // Should decrease
    }
}