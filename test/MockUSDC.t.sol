// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MockUSDC} from "../src/tokens/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDCTest is Test {
    MockUSDC public token;
    address public owner;
    address public user1;
    address public user2;
    address public nonOwner;

    uint256 public constant INITIAL_SUPPLY = 10_000_000 * 1e6; // 10M USDC (6 decimals)

    // Events from ERC20 and Ownable
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        nonOwner = address(0x3);

        token = new MockUSDC(address(this));
        token.mint(address(this), INITIAL_SUPPLY);
    }

    // =========================
    // CONSTRUCTOR TESTS
    // =========================

    function test_constructor_SetsCorrectParameters() public view{
        assertEq(token.name(), "Mock USDC");
        assertEq(token.symbol(), "USDC");
        assertEq(token.decimals(), 6); // USDC has 6 decimals
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.owner(), owner);
    }

    function test_constructor_EmitsTransferEvent() public {
        MockUSDC newToken = new MockUSDC(address(this));
        
        // Expect Transfer event from minting
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), INITIAL_SUPPLY);
        
        newToken.mint(address(this), INITIAL_SUPPLY);
    }

    function test_constructor_ZeroInitialSupply() public {
        MockUSDC zeroToken = new MockUSDC(address(0x1));
        
        assertEq(zeroToken.totalSupply(), 0);
        assertEq(zeroToken.balanceOf(owner), 0);
    }

    // =========================
    // MINT FUNCTION TESTS
    // =========================

    function test_mint_OnlyOwnerCanMint() public {
        uint256 mintAmount = 1000 * 1e6; // 1000 USDC
        uint256 balanceBefore = token.balanceOf(user1);
        uint256 totalSupplyBefore = token.totalSupply();

        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), balanceBefore + mintAmount);
        assertEq(token.totalSupply(), totalSupplyBefore + mintAmount);
    }

    function test_mint_EmitsTransferEvent() public {
        uint256 mintAmount = 500 * 1e6; // 500 USDC

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, mintAmount);

        token.mint(user1, mintAmount);
    }

    function test_mint_NonOwnerCannotMint() public {
        uint256 mintAmount = 1000 * 1e6;

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        token.mint(user1, mintAmount);
    }

    function test_mint_ZeroAmount() public {
        uint256 balanceBefore = token.balanceOf(user1);
        uint256 totalSupplyBefore = token.totalSupply();

        token.mint(user1, 0);

        assertEq(token.balanceOf(user1), balanceBefore);
        assertEq(token.totalSupply(), totalSupplyBefore);
    }

    function test_mint_ToZeroAddress() public {
        uint256 mintAmount = 1000 * 1e6;

        // ERC20 should revert when minting to zero address
        vm.expectRevert();
        token.mint(address(0), mintAmount);
    }

    function test_mint_LargeAmount() public {
        uint256 mintAmount = 1_000_000 * 1e6; // 1M USDC
        uint256 balanceBefore = token.balanceOf(user1);
        uint256 totalSupplyBefore = token.totalSupply();

        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), balanceBefore + mintAmount);
        assertEq(token.totalSupply(), totalSupplyBefore + mintAmount);
    }

    // =========================
    // STANDARD ERC20 TESTS
    // =========================

    function test_transfer_Success() public {
        uint256 transferAmount = 1000 * 1e6; // 1000 USDC
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 user1BalanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, transferAmount);

        bool success = token.transfer(user1, transferAmount);

        assertTrue(success);
        assertEq(token.balanceOf(owner), ownerBalanceBefore - transferAmount);
        assertEq(token.balanceOf(user1), user1BalanceBefore + transferAmount);
    }

    function test_transfer_InsufficientBalance() public {
        uint256 transferAmount = INITIAL_SUPPLY + 1;

        vm.expectRevert();
        token.transfer(user1, transferAmount);
    }

    function test_transfer_ToZeroAddress() public {
        uint256 transferAmount = 1000 * 1e6;

        vm.expectRevert();
        token.transfer(address(0), transferAmount);
    }

    function test_approve_Success() public {
        uint256 approveAmount = 1000 * 1e6;

        vm.expectEmit(true, true, false, true);
        emit Approval(owner, user1, approveAmount);

        bool success = token.approve(user1, approveAmount);

        assertTrue(success);
        assertEq(token.allowance(owner, user1), approveAmount);
    }

    function test_approve_ZeroAmount() public {
        uint256 approveAmount = 0;

        bool success = token.approve(user1, approveAmount);

        assertTrue(success);
        assertEq(token.allowance(owner, user1), approveAmount);
    }

    function test_approve_OverwriteApproval() public {
        uint256 firstApproval = 1000 * 1e6;
        uint256 secondApproval = 2000 * 1e6;

        token.approve(user1, firstApproval);
        assertEq(token.allowance(owner, user1), firstApproval);

        token.approve(user1, secondApproval);
        assertEq(token.allowance(owner, user1), secondApproval);
    }

    function test_transferFrom_Success() public {
        uint256 approveAmount = 1000 * 1e6;
        uint256 transferAmount = 500 * 1e6;

        // First approve
        token.approve(user1, approveAmount);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 user2BalanceBefore = token.balanceOf(user2);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user2, transferAmount);

        bool success = token.transferFrom(owner, user2, transferAmount);

        assertTrue(success);
        assertEq(token.balanceOf(owner), ownerBalanceBefore - transferAmount);
        assertEq(token.balanceOf(user2), user2BalanceBefore + transferAmount);
        assertEq(token.allowance(owner, user1), approveAmount - transferAmount);
    }

    function test_transferFrom_InsufficientAllowance() public {
        uint256 approveAmount = 500 * 1e6;
        uint256 transferAmount = 1000 * 1e6;

        token.approve(user1, approveAmount);

        vm.prank(user1);
        vm.expectRevert();
        token.transferFrom(owner, user2, transferAmount);
    }

    function test_transferFrom_InsufficientBalance() public {
        uint256 approveAmount = type(uint256).max;
        uint256 transferAmount = INITIAL_SUPPLY + 1;

        token.approve(user1, approveAmount);

        vm.prank(user1);
        vm.expectRevert();
        token.transferFrom(owner, user2, transferAmount);
    }

    // =========================
    // OWNERSHIP TESTS
    // =========================

    function test_transferOwnership_Success() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, user1);

        token.transferOwnership(user1);

        assertEq(token.owner(), user1);
    }

    function test_transferOwnership_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        token.transferOwnership(user1);
    }

    function test_transferOwnership_ToZeroAddress() public {
        vm.expectRevert();
        token.transferOwnership(address(0));
    }

    function test_renounceOwnership() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, address(0));

        token.renounceOwnership();

        assertEq(token.owner(), address(0));
    }

    // =========================
    // INTEGRATION TESTS
    // =========================

    function test_mintAndTransfer_Integration() public {
        uint256 mintAmount = 1000 * 1e6;
        uint256 transferAmount = 300 * 1e6;

        // Mint to user1
        token.mint(user1, mintAmount);
        assertEq(token.balanceOf(user1), mintAmount);

        // User1 transfers to user2
        vm.prank(user1);
        token.transfer(user2, transferAmount);

        assertEq(token.balanceOf(user1), mintAmount - transferAmount);
        assertEq(token.balanceOf(user2), transferAmount);
    }

    function test_multipleMintsAndTransfers() public {
        // Multiple mints to different users
        token.mint(user1, 1000 * 1e6);
        token.mint(user2, 2000 * 1e6);

        uint256 totalSupplyAfterMints = INITIAL_SUPPLY + 3000 * 1e6;
        assertEq(token.totalSupply(), totalSupplyAfterMints);

        // Transfers between users
        vm.prank(user1);
        token.transfer(user2, 500 * 1e6);

        assertEq(token.balanceOf(user1), 500 * 1e6);
        assertEq(token.balanceOf(user2), 2500 * 1e6);
        assertEq(token.totalSupply(), totalSupplyAfterMints); // Total supply unchanged
    }

    // =========================
    // FUZZ TESTS
    // =========================

    function testFuzz_mint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount <= type(uint128).max); // Avoid overflow issues

        uint256 balanceBefore = token.balanceOf(to);
        uint256 totalSupplyBefore = token.totalSupply();

        token.mint(to, amount);

        assertEq(token.balanceOf(to), balanceBefore + amount);
        assertEq(token.totalSupply(), totalSupplyBefore + amount);
    }

    function testFuzz_transfer(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != owner); // Prevent self-transfers which can cause balance calculation issues
        amount = bound(amount, 0, INITIAL_SUPPLY);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 toBalanceBefore = token.balanceOf(to);

        token.transfer(to, amount);

        assertEq(token.balanceOf(owner), ownerBalanceBefore - amount);
        assertEq(token.balanceOf(to), toBalanceBefore + amount);
    }

    function testFuzz_approve(address spender, uint256 amount) public {
        vm.assume(spender != address(0));

        token.approve(spender, amount);

        assertEq(token.allowance(owner, spender), amount);
    }

    // =========================
    // DECIMAL PRECISION TESTS
    // =========================

    function test_smallAmounts_OneMicroUSDC() public {
        uint256 microAmount = 1; // 0.000001 USDC
        
        token.mint(user1, microAmount);
        assertEq(token.balanceOf(user1), microAmount);

        vm.prank(user1);
        token.transfer(user2, microAmount);
        assertEq(token.balanceOf(user2), microAmount);
        assertEq(token.balanceOf(user1), 0);
    }

    function test_precisionHandling_6Decimals() public {
        uint256 oneDollar = 1e6; // 1 USDC with 6 decimals
        uint256 oneHundredth = 1e4; // 0.01 USDC
        uint256 oneMicro = 1; // 0.000001 USDC

        token.mint(user1, oneDollar + oneHundredth + oneMicro);
        
        assertEq(token.balanceOf(user1), 1010001); // 1.010001 USDC
        assertEq(token.decimals(), 6);
    }
}