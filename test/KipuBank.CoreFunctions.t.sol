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
 * @title KipuBank Core Functions Test Suite
 * @dev Tests for main banking functionality that wasn't covered yet
 */
contract KipuBankCoreFunctionsTest is Test {
    
    KipuBank public bank;
    KipuGLD public kgld;
    MockUSDC public usdc;
    MockV3Aggregator public priceFeed;
    MockUniswapV2Router public router;
    
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public owner = address(this);
    
    uint256 constant INITIAL_ETH_PRICE = 3000e8; // $3000
    uint256 constant WITHDRAW_MAX = 1 ether;
    uint256 constant BANK_CAP = 100; // Max 100 transactions
    uint256 constant BANK_USD_CAP = 50000e18; // $50k
    
    // Events to test (matching the contract's event signatures)
    event depositDone(address client, uint256 amount);
    event withdrawalDone(address client, uint256 amount);
    event erc20DepositDone(address indexed token, address indexed client, uint256 amount);
    event erc20WithdrawalDone(address indexed token, address indexed client, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);
    
    function setUp() public {
        // Deploy all contracts
        kgld = new KipuGLD(address(this), 1_000_000e18);
        usdc = new MockUSDC(address(this));
        usdc.mint(address(this), 10_000_000e6); // 10M USDC
        
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
        
        // Setup users with ETH and tokens
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        
        // Transfer tokens to users
        kgld.transfer(user1, 1000e18);
        kgld.transfer(user2, 1000e18);
        
        usdc.mint(user1, 10000e6); // 10k USDC
        usdc.mint(user2, 10000e6); // 10k USDC
        
        // Setup router with liquidity
        vm.deal(address(router), 100 ether);
        usdc.mint(address(router), 1_000_000e6); // 1M USDC to router
        kgld.transfer(address(router), 10000e18);
    }
    
    // =========================
    // DEPOSIT FUNCTION TESTS
    // =========================
    
    function test_deposit_Success() public {
        uint256 depositAmount = 1 ether;
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit depositDone(user1, depositAmount);
        
        bank.deposit{value: depositAmount}();
        
        assertEq(bank.balances(user1), depositAmount);
        assertGt(bank.bankUsdLiabilities(), 0); // Should track USD value
    }
    
    function test_deposit_UpdatesTransactionCounter() public {
        uint256 depositAmount = 0.5 ether;
        (uint256 txBefore,) = bank.bankStats();
        
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        (uint256 txAfter,) = bank.bankStats();
        assertEq(txAfter, txBefore + 1);
    }
    
    function test_deposit_UpdatesBankUsdLiabilities() public {
        uint256 depositAmount = 1 ether;
        uint256 liabilitiesBefore = bank.bankUsdLiabilities();
        
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        uint256 liabilitiesAfter = bank.bankUsdLiabilities();
        assertGt(liabilitiesAfter, liabilitiesBefore);
        
        // Should roughly equal ETH amount * ETH price
        uint256 expectedUsd = (depositAmount * INITIAL_ETH_PRICE) / 1e8; // Price has 8 decimals
        assertApproxEqRel(liabilitiesAfter - liabilitiesBefore, expectedUsd, 0.01e18); // 1% tolerance
    }
    
    function test_deposit_RevertsWhenZeroValue() public {
        vm.prank(user1);
        vm.expectRevert(); // Should trigger nonZeroValue modifier
        bank.deposit{value: 0}();
    }
    
    function test_deposit_RevertsWhenExceedsTransactionCap() public {
        // Make 100 transactions to reach the cap
        for(uint i = 0; i < BANK_CAP; i++) {
            vm.deal(user1, 1 ether);
            vm.prank(user1);
            bank.deposit{value: 0.01 ether}();
        }
        
        // Now the 101st transaction should revert
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(); // Should trigger underTxCap modifier
        bank.deposit{value: 0.01 ether}();
    }
    
    function test_deposit_RevertsWhenExceedsUsdCap() public {
        // BANK_USD_CAP = 50000e18 (50000 USD in 18 decimals)
        // ETH price = 300000000 (8 decimals) = $3000
        // To exceed cap: need > 50000/3000 = 16.67 ETH
        uint256 ethToExceedCap = 17 ether; // This should be > $51000 USD
        vm.deal(user1, ethToExceedCap);
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger underUsdCap modifier
        bank.deposit{value: ethToExceedCap}();
    }
    
    function test_deposit_RevertsWhenPaused() public {
        // Pause the contract
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger whenNotPaused modifier
        bank.deposit{value: 1 ether}();
    }
    
    // =========================
    // WITHDRAWAL FUNCTION TESTS
    // =========================
    
    function test_withdrawal_Success() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 1 ether;
        
        // First deposit
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        // Then withdraw
        uint256 balanceBefore = user1.balance;
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit withdrawalDone(user1, withdrawAmount);
        
        bank.withdrawal(withdrawAmount);
        
        uint256 balanceAfter = user1.balance;
        assertEq(balanceAfter - balanceBefore, withdrawAmount);
        assertEq(bank.balances(user1), depositAmount - withdrawAmount);
    }
    
    function test_withdrawal_UpdatesCounters() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 1 ether;
        
        // Setup
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        (,uint256 withdrawalsBefore) = bank.bankStats();
        
        // Withdraw
        vm.prank(user1);
        bank.withdrawal(withdrawAmount);
        
        (,uint256 withdrawalsAfter) = bank.bankStats();
        assertEq(withdrawalsAfter, withdrawalsBefore + 1);
    }
    
    function test_withdrawal_UpdatesBankUsdLiabilities() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 1 ether;
        
        // Setup
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        uint256 liabilitiesBefore = bank.bankUsdLiabilities();
        
        // Withdraw
        vm.prank(user1);
        bank.withdrawal(withdrawAmount);
        
        uint256 liabilitiesAfter = bank.bankUsdLiabilities();
        assertLt(liabilitiesAfter, liabilitiesBefore); // Should decrease
    }
    
    function test_withdrawal_RevertsWithInsufficientFunds() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 2 ether; // More than deposited
        
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger hasFunds modifier
        bank.withdrawal(withdrawAmount);
    }
    
    function test_withdrawal_RevertsWhenExceedsWithdrawCap() public {
        uint256 depositAmount = 5 ether;
        uint256 excessiveWithdraw = WITHDRAW_MAX + 1 ether;
        
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger withinWithdrawCap modifier
        bank.withdrawal(excessiveWithdraw);
    }
    
    function test_withdrawal_RevertsWhenPaused() public {
        uint256 depositAmount = 2 ether;
        
        vm.prank(user1);
        bank.deposit{value: depositAmount}();
        
        // Pause the contract
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert(); // Should trigger whenNotPaused modifier
        bank.withdrawal(1 ether);
    }
    
    // =========================
    // BANK STATS TESTS
    // =========================
    
    function test_bankStats_InitialState() public {
        (uint256 deposits, uint256 withdrawals) = bank.bankStats();
        assertEq(deposits, 0);
        assertEq(withdrawals, 0);
    }
    
    function test_bankStats_TracksDepositsAndWithdrawals() public {
        // Multiple deposits
        vm.prank(user1);
        bank.deposit{value: 1 ether}();
        
        vm.prank(user2);
        bank.deposit{value: 0.5 ether}();
        
        (uint256 deposits,) = bank.bankStats();
        assertEq(deposits, 2);
        
        // Withdrawal
        vm.prank(user1);
        bank.withdrawal(0.5 ether);
        
        (,uint256 withdrawals) = bank.bankStats();
        assertEq(withdrawals, 1);
    }
    
    // =========================
    // PAUSE/UNPAUSE TESTS  
    // =========================
    
    function test_pause_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert(); // Should revert for non-owner
        bank.pause();
    }
    
    function test_pause_Success() public {
        vm.expectEmit(false, false, false, true);
        emit Paused(address(this));
        
        bank.pause();
        assertTrue(bank.paused());
    }
    
    function test_unpause_OnlyOwner() public {
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert(); // Should revert for non-owner
        bank.unpause();
    }
    
    function test_unpause_Success() public {
        bank.pause();
        
        vm.expectEmit(false, false, false, true);
        emit Unpaused(address(this));
        
        bank.unpause();
        assertFalse(bank.paused());
    }
    
    // =========================
    // PRICE FUNCTION TESTS
    // =========================
    
    function test_ethToUsdConversion() public {
        uint256 ethAmount = 1 ether;
        
        // Do a deposit to trigger price conversion
        vm.prank(user1);
        bank.deposit{value: ethAmount}();
        
        uint256 liabilities = bank.bankUsdLiabilities();
        uint256 expectedUsd = (ethAmount * INITIAL_ETH_PRICE) / 1e8;
        
        assertApproxEqRel(liabilities, expectedUsd, 0.01e18); // 1% tolerance
    }
    
    function test_priceUpdateAffectsDeposits() public {
        uint256 ethAmount = 1 ether;
        
        // Deposit at initial price
        vm.prank(user1);
        bank.deposit{value: ethAmount}();
        uint256 liabilities1 = bank.bankUsdLiabilities();
        
        // Update price
        uint256 newPrice = 4000e8; // $4000
        priceFeed.updateAnswer(int256(newPrice));
        
        // New deposit should use new price
        vm.prank(user2);
        bank.deposit{value: ethAmount}();
        uint256 liabilities2 = bank.bankUsdLiabilities();
        
        // Second deposit should add more USD value due to higher ETH price
        assertGt(liabilities2 - liabilities1, liabilities1);
    }
    
    // =========================
    // INTEGRATION TESTS
    // =========================
    
    function test_fullCycleDepositWithdraw() public {
        uint256 amount = 1 ether;
        
        // Full cycle test
        vm.startPrank(user1);
        
        uint256 initialBalance = user1.balance;
        
        // Deposit
        bank.deposit{value: amount}();
        assertEq(bank.balances(user1), amount);
        
        // Withdraw
        bank.withdrawal(amount);
        
        vm.stopPrank();
        
        // Should be back to original balance (minus gas)
        assertApproxEqAbs(user1.balance, initialBalance, 0.01 ether); // Account for gas
        assertEq(bank.balances(user1), 0);
    }
    
    function test_multipleUsersDepositWithdraw() public {
        uint256 amount1 = 0.9 ether;
        uint256 amount2 = 0.8 ether;
        
        // User 1 deposits
        vm.prank(user1);
        bank.deposit{value: amount1}();
        
        // User 2 deposits  
        vm.prank(user2);
        bank.deposit{value: amount2}();
        
        // Check individual balances
        assertEq(bank.balances(user1), amount1);
        assertEq(bank.balances(user2), amount2);
        
        // Check stats
        (uint256 deposits,) = bank.bankStats();
        assertEq(deposits, 2);
        
        // Both withdraw
        vm.prank(user1);
        bank.withdrawal(amount1);
        
        vm.prank(user2);
        bank.withdrawal(amount2);
        
        // Check final state
        assertEq(bank.balances(user1), 0);
        assertEq(bank.balances(user2), 0);
        
        (,uint256 withdrawals) = bank.bankStats();
        assertEq(withdrawals, 2);
    }
    
    // =========================
    // FUZZ TESTS
    // =========================
    
    function testFuzz_deposit(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 16 ether); // Up to ~$48k at $3k ETH
        
        // Skip if would exceed USD cap
        uint256 usdValue = (amount * INITIAL_ETH_PRICE * 1e10) / 1e18; // Use correct conversion
        if (usdValue > BANK_USD_CAP) return;
        
        vm.deal(user1, amount);
        
        vm.prank(user1);
        bank.deposit{value: amount}();
        
        assertEq(bank.balances(user1), amount);
        assertGt(bank.bankUsdLiabilities(), 0);
    }
    
    function testFuzz_depositWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 0.1 ether, 16 ether); // Up to ~$48k at $3k ETH
        withdrawAmount = bound(withdrawAmount, 0.001 ether, min(depositAmount, WITHDRAW_MAX));
        
        // Skip if would exceed USD cap
        uint256 usdValue = (depositAmount * INITIAL_ETH_PRICE * 1e10) / 1e18; // Use correct conversion
        if (usdValue > BANK_USD_CAP) return;
        
        vm.deal(user1, depositAmount);
        
        vm.startPrank(user1);
        
        // Deposit
        bank.deposit{value: depositAmount}();
        assertEq(bank.balances(user1), depositAmount);
        
        // Withdraw
        uint256 balanceBefore = user1.balance;
        bank.withdrawal(withdrawAmount);
        
        vm.stopPrank();
        
        assertEq(bank.balances(user1), depositAmount - withdrawAmount);
        assertEq(user1.balance - balanceBefore, withdrawAmount);
    }
    
    // =========================
    // HELPER FUNCTIONS
    // =========================
    
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}