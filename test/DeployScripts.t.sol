// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {KipuGLD} from "../src/tokens/KipuGLD.sol";
import {MockUSDC} from "../src/tokens/MockUSDC.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";

/**
 * @title DeployScripts Test Suite
 * @dev Comprehensive tests for deployment scripts of all contracts
 */
contract DeployScriptsTest is Test {
    // =========================
    // EVENTS FOR TESTING
    // =========================
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // =========================
    // SETUP
    // =========================

    function setUp() public {
        // Test setup
    }

    // =========================
    // DEPLOY KGLD TESTS
    // =========================

    function test_deployKGLD_Success() public {
        uint256 initialSupply = 1_000_000 * 1e18; // 1M KGLD
        
        // Deploy the token directly
        KipuGLD token = new KipuGLD(address(this), initialSupply);
        
        // Verify deployment
        assertTrue(address(token) != address(0));
        assertEq(token.name(), "Kipu Gold");
        assertEq(token.symbol(), "KGLD");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.owner(), address(this));
    }

    function test_deployKGLD_OwnerReceivesTokens() public {
        uint256 initialSupply = 1_000_000 * 1e18;
        
        KipuGLD token = new KipuGLD(address(this), initialSupply);
        
        // Verify owner balance
        assertEq(token.balanceOf(address(this)), initialSupply);
    }

    function test_deployKGLD_EmitsTransferEvent() public {
        uint256 initialSupply = 1_000_000 * 1e18;
        
        // Expect Transfer event from zero address to owner
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), initialSupply);
        
        new KipuGLD(address(this), initialSupply);
    }

    function test_deployKGLD_OwnershipIsCorrect() public {
        uint256 initialSupply = 1_000_000 * 1e18;
        
        KipuGLD token = new KipuGLD(address(this), initialSupply);
        
        // Verify ownership
        assertEq(token.owner(), address(this));
        
        // Test ownership transfer
        address newOwner = makeAddr("newOwner");
        
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), newOwner);
        
        token.transferOwnership(newOwner);
        assertEq(token.owner(), newOwner);
    }

    // =========================
    // DEPLOY USDC TESTS
    // =========================

    function test_deployUSDC_Success() public {
        // Deploy the token directly
        MockUSDC token = new MockUSDC(address(this));
        
        // Mint initial supply
        uint256 initialSupply = 10_000_000 * 1e6; // 10M USDC
        token.mint(address(this), initialSupply);
        
        // Verify deployment
        assertTrue(address(token) != address(0));
        assertEq(token.name(), "Mock USDC");
        assertEq(token.symbol(), "USDC");
        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.owner(), address(this));
    }

    function test_deployUSDC_OwnerReceivesTokens() public {
        uint256 initialSupply = 10_000_000 * 1e6;
        
        MockUSDC token = new MockUSDC(address(this));
        token.mint(address(this), initialSupply);
        
        // Verify owner balance
        assertEq(token.balanceOf(address(this)), initialSupply);
    }

    function test_deployUSDC_CorrectDecimals() public {
        uint256 initialSupply = 10_000_000 * 1e6;
        
        MockUSDC token = new MockUSDC(address(this));
        token.mint(address(this), initialSupply);
        
        // USDC should have 6 decimals (not 18 like most ERC20s)
        assertEq(token.decimals(), 6);
        
        // Verify amounts are in the correct scale
        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.balanceOf(address(this)), initialSupply);
    }

    // =========================
    // DEPLOY MOCK V3 AGGREGATOR TESTS
    // =========================

    function test_deployMockV3_Success() public {
        uint8 decimals_ = 8;
        int256 initialAnswer = 3000 * 1e8; // $3000 ETH
        
        // Deploy the aggregator directly
        MockV3Aggregator aggregator = new MockV3Aggregator(decimals_, initialAnswer);
        
        // Verify deployment
        assertTrue(address(aggregator) != address(0));
        assertEq(aggregator.decimals(), 8);
        
        (, int256 price,,,) = aggregator.latestRoundData();
        assertEq(price, initialAnswer);
    }

    function test_deployMockV3_LatestRoundData() public {
        uint8 decimals_ = 8;
        int256 initialAnswer = 3000 * 1e8;
        
        MockV3Aggregator aggregator = new MockV3Aggregator(decimals_, initialAnswer);
        
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.latestRoundData();
        
        // Verify all fields are set (our simple mock returns 0 for metadata fields)
        assertEq(roundId, 0);
        assertEq(price, initialAnswer);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }

    function test_deployMockV3_UpdateAnswer() public {
        uint8 decimals_ = 8;
        int256 initialAnswer = 3000 * 1e8;
        int256 newAnswer = 3500 * 1e8;
        
        MockV3Aggregator aggregator = new MockV3Aggregator(decimals_, initialAnswer);
        
        // Update price and verify
        aggregator.updateAnswer(newAnswer);
        
        (,int256 updatedPrice,,,) = aggregator.latestRoundData();
        assertEq(updatedPrice, newAnswer);
    }

    // =========================
    // INTEGRATION TESTS
    // =========================

    function test_deployAll_Integration() public {
        // Deploy all contracts
        uint256 kgldSupply = 1_000_000 * 1e18;
        uint256 usdcSupply = 10_000_000 * 1e6;
        uint8 aggregatorDecimals = 8;
        int256 initialPrice = 3000 * 1e8;
        
        KipuGLD kgld = new KipuGLD(address(this), kgldSupply);
        MockUSDC usdc = new MockUSDC(address(this));
        MockV3Aggregator aggregator = new MockV3Aggregator(aggregatorDecimals, initialPrice);
        
        // Verify all contracts are deployed
        assertTrue(address(kgld) != address(0));
        assertTrue(address(usdc) != address(0));
        assertTrue(address(aggregator) != address(0));
        
        // Mint USDC tokens
        usdc.mint(address(this), usdcSupply);
        
        // Verify they work together (basic functionality)
        assertEq(kgld.balanceOf(address(this)), kgldSupply);
        assertEq(usdc.balanceOf(address(this)), usdcSupply);
        
        (, int256 price,,,) = aggregator.latestRoundData();
        assertEq(price, initialPrice);
    }

    function test_deployAll_CompatibleWithKipuBank() public {
        // Deploy supporting contracts
        uint256 kgldSupply = 1_000_000 * 1e18;
        uint256 usdcSupply = 10_000_000 * 1e6;
        uint8 aggregatorDecimals = 8;
        int256 initialPrice = 2500 * 1e8; // $2500 ETH
        
        KipuGLD kgld = new KipuGLD(address(this), kgldSupply);
        MockUSDC usdc = new MockUSDC(address(this));
        MockV3Aggregator aggregator = new MockV3Aggregator(aggregatorDecimals, initialPrice);
        
        // Test that decimals are compatible
        assertEq(kgld.decimals(), 18); // Standard ERC20
        assertEq(usdc.decimals(), 6);  // USDC standard
        assertEq(aggregator.decimals(), 8); // Chainlink standard
        
        // Test that price feeds work
        (, int256 ethPrice,,,) = aggregator.latestRoundData();
        assertTrue(ethPrice > 0);
        assertTrue(ethPrice > 1000 * 1e8); // Reasonable ETH price > $1000
    }

    // =========================
    // FUZZ TESTS
    // =========================

    function testFuzz_deployKGLD_AnySupply(uint256 supply) public {
        // Bound to reasonable values to avoid overflow
        supply = bound(supply, 1, type(uint128).max);
        
        KipuGLD token = new KipuGLD(address(this), supply);
        
        assertEq(token.totalSupply(), supply);
        assertEq(token.balanceOf(address(this)), supply);
    }

    function testFuzz_deployUSDC_AnySupply(uint256 supply) public {
        // Bound to reasonable values for 6 decimals
        supply = bound(supply, 1, type(uint64).max);
        
        MockUSDC token = new MockUSDC(address(this));
        token.mint(address(this), supply);
        
        assertEq(token.totalSupply(), supply);
        assertEq(token.balanceOf(address(this)), supply);
        assertEq(token.decimals(), 6);
    }

    function testFuzz_deployMockV3_AnyPrice(int256 price) public {
        // Bound to reasonable price values (positive and not too large)
        price = bound(price, 1, type(int128).max);
        
        MockV3Aggregator aggregator = new MockV3Aggregator(8, price);
        
        assertEq(aggregator.decimals(), 8);
        
        (,int256 roundPrice,,,) = aggregator.latestRoundData();
        assertEq(roundPrice, price);
    }

    // =========================
    // ERROR TESTS
    // =========================

    function test_deployKGLD_ZeroSupply() public {
        // Should be able to deploy with zero supply
        KipuGLD token = new KipuGLD(address(this), 0);
        
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_deployMockV3_ZeroPrice() public {
        // Should be able to deploy with zero price
        MockV3Aggregator aggregator = new MockV3Aggregator(8, 0);
        
        (,int256 price,,,) = aggregator.latestRoundData();
        assertEq(price, 0);
    }

    function test_deployMockV3_NegativePrice() public {
        // Should be able to deploy with negative price (some feeds can be negative)
        int256 negativePrice = -100 * 1e8;
        MockV3Aggregator aggregator = new MockV3Aggregator(8, negativePrice);
        
        (,int256 price,,,) = aggregator.latestRoundData();
        assertEq(price, negativePrice);
    }
}