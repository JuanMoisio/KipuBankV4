// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {KipuGLD} from "../src/tokens/KipuGLD.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract KipuGLDTest is Test {
    KipuGLD public token;
    address public owner;
    address public user1;
    address public user2;
    address public nonOwner;

    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18; // 1M tokens

    // Events from ERC20 and Ownable
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        nonOwner = address(0x3);

        token = new KipuGLD(address(this), INITIAL_SUPPLY);
    }

    // =========================
    // CONSTRUCTOR TESTS
    // =========================

    function test_constructor_SetsCorrectParameters() public view{
        assertEq(token.name(), "Kipu Gold");
        assertEq(token.symbol(), "KGLD");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.owner(), owner);
    }

    function test_constructor_EmitsTransferEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), owner, INITIAL_SUPPLY);
        
        new KipuGLD(address(this), INITIAL_SUPPLY);
    }

    // =========================
    // MINT FUNCTION TESTS
    // =========================

    function test_mint_OnlyOwnerCanMint() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 balanceBefore = token.balanceOf(user1);
        uint256 totalSupplyBefore = token.totalSupply();

        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), balanceBefore + mintAmount);
        assertEq(token.totalSupply(), totalSupplyBefore + mintAmount);
    }

    function test_mint_EmitsTransferEvent() public {
        uint256 mintAmount = 500 * 1e18;

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, mintAmount);

        token.mint(user1, mintAmount);
    }

    function test_mint_NonOwnerCannotMint() public {
        uint256 mintAmount = 1000 * 1e18;

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
        uint256 mintAmount = 1000 * 1e18;

        // ERC20 should revert when minting to zero address
        vm.expectRevert();
        token.mint(address(0), mintAmount);
    }

    // =========================
    // BURN FUNCTION TESTS
    // =========================

    function test_burn_OnlyOwnerCanBurn() public {
        uint256 burnAmount = 1000 * 1e18;
        uint256 balanceBefore = token.balanceOf(owner);
        uint256 totalSupplyBefore = token.totalSupply();

        token.burn(burnAmount);

        assertEq(token.balanceOf(owner), balanceBefore - burnAmount);
        assertEq(token.totalSupply(), totalSupplyBefore - burnAmount);
    }

    function test_burn_EmitsTransferEvent() public {
        uint256 burnAmount = 500 * 1e18;

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, address(0), burnAmount);

        token.burn(burnAmount);
    }

    function test_burn_NonOwnerCanBurnOwnTokens() public {
        uint256 transferAmount = 1000 * 1e18;
        uint256 burnAmount = 500 * 1e18;

        // Transfer tokens to nonOwner first
        token.transfer(nonOwner, transferAmount);
        
        // NonOwner should be able to burn their own tokens
        vm.prank(nonOwner);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(nonOwner, address(0), burnAmount);
        
        token.burn(burnAmount);
        
        // Verify burn worked
        assertEq(token.balanceOf(nonOwner), transferAmount - burnAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }

    function test_burn_InsufficientBalance() public {
        uint256 burnAmount = INITIAL_SUPPLY + 1;

        vm.expectRevert();
        token.burn(burnAmount);
    }

    function test_burn_ZeroAmount() public {
        uint256 balanceBefore = token.balanceOf(owner);
        uint256 totalSupplyBefore = token.totalSupply();

        token.burn(0);

        assertEq(token.balanceOf(owner), balanceBefore);
        assertEq(token.totalSupply(), totalSupplyBefore);
    }

    // =========================
    // STANDARD ERC20 TESTS
    // =========================

    function test_transfer_Success() public {
        uint256 transferAmount = 1000 * 1e18;
        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 user1BalanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, user1, transferAmount);

        bool success = token.transfer(user1, transferAmount);

        assertTrue(success);
        assertEq(token.balanceOf(owner), ownerBalanceBefore - transferAmount);
        assertEq(token.balanceOf(user1), user1BalanceBefore + transferAmount);
    }

    function test_approve_Success() public {
        uint256 approveAmount = 1000 * 1e18;

        vm.expectEmit(true, true, false, true);
        emit Approval(owner, user1, approveAmount);

        bool success = token.approve(user1, approveAmount);

        assertTrue(success);
        assertEq(token.allowance(owner, user1), approveAmount);
    }

    function test_transferFrom_Success() public {
        uint256 approveAmount = 1000 * 1e18;
        uint256 transferAmount = 500 * 1e18;

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

    function test_renounceOwnership() public {
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, address(0));

        token.renounceOwnership();

        assertEq(token.owner(), address(0));
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

    function testFuzz_burn(uint256 amount) public {
        amount = bound(amount, 0, INITIAL_SUPPLY);

        uint256 balanceBefore = token.balanceOf(owner);
        uint256 totalSupplyBefore = token.totalSupply();

        token.burn(amount);

        assertEq(token.balanceOf(owner), balanceBefore - amount);
        assertEq(token.totalSupply(), totalSupplyBefore - amount);
    }

    function testFuzz_transfer(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, INITIAL_SUPPLY);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 toBalanceBefore = token.balanceOf(to);

        token.transfer(to, amount);

        assertEq(token.balanceOf(owner), ownerBalanceBefore - amount);
        assertEq(token.balanceOf(to), toBalanceBefore + amount);
    }
}