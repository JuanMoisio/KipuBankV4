// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";

contract MockV3AggregatorTest is Test {
    MockV3Aggregator public aggregator;
    
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_ANSWER = 3000 * 1e8; // $3000
    
    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER);
    }
    
    // =========================
    // BASIC FUNCTIONALITY TESTS
    // =========================
    
    function test_constructor_SetsCorrectValues() public {
        assertEq(aggregator.decimals(), DECIMALS);
        
        (, int256 price,,,) = aggregator.latestRoundData();
        assertEq(price, INITIAL_ANSWER);
    }
    
    function test_latestRoundData_ReturnsCorrectValues() public {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.latestRoundData();
        
        // Basic validation
        assertEq(roundId, 0);
        assertEq(answer, INITIAL_ANSWER);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }
    
    function test_updateAnswer_ChangesPrice() public {
        int256 newAnswer = 4000 * 1e8;
        
        aggregator.updateAnswer(newAnswer);
        
        (, int256 updatedPrice,,,) = aggregator.latestRoundData();
        assertEq(updatedPrice, newAnswer);
    }
    
    // =========================
    // EDGE CASE TESTS
    // =========================
    
    function test_updateAnswer_ZeroPrice() public {
        aggregator.updateAnswer(0);
        
        (, int256 price,,,) = aggregator.latestRoundData();
        assertEq(price, 0);
    }
    
    function test_updateAnswer_NegativePrice() public {
        int256 negativePrice = -100 * 1e8;
        aggregator.updateAnswer(negativePrice);
        
        (, int256 price,,,) = aggregator.latestRoundData();
        assertEq(price, negativePrice);
    }
    
    function test_decimals_IsImmutable() public {
        // Test that decimals remain constant
        uint8 initialDecimals = aggregator.decimals();
        
        // Update answer shouldn't affect decimals
        aggregator.updateAnswer(5000 * 1e8);
        
        assertEq(aggregator.decimals(), initialDecimals);
        assertEq(aggregator.decimals(), DECIMALS);
    }
    
    // =========================
    // INTEGRATION TESTS
    // =========================
    
    function test_multipleUpdates_WorkCorrectly() public {
        int256[] memory prices = new int256[](3);
        prices[0] = 3500 * 1e8;
        prices[1] = 2800 * 1e8;
        prices[2] = 4200 * 1e8;
        
        for (uint256 i = 0; i < prices.length; i++) {
            aggregator.updateAnswer(prices[i]);
            
            (, int256 currentPrice,,,) = aggregator.latestRoundData();
            assertEq(currentPrice, prices[i]);
        }
    }
    
    function test_chainlinkInterface_Compatible() public {
        // Test that our mock follows Chainlink interface standards
        
        // Standard ETH/USD feed has 8 decimals
        assertEq(aggregator.decimals(), 8);
        
        // Should return valid round data
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.latestRoundData();
        
        // All values should be accessible (no revert)
        assertTrue(true); // If we get here, no revert occurred
        assertEq(answer, INITIAL_ANSWER);
    }
    
    // =========================
    // FUZZ TESTS
    // =========================
    
    function testFuzz_updateAnswer_AnyPrice(int256 price) public {
        // Bound to reasonable values
        price = bound(price, type(int128).min, type(int128).max);
        
        aggregator.updateAnswer(price);
        
        (, int256 updatedPrice,,,) = aggregator.latestRoundData();
        assertEq(updatedPrice, price);
    }
    
    function testFuzz_constructor_AnyDecimals(uint8 decimals_, int256 initialPrice) public {
        // Bound decimals to reasonable values (0-18 is typical for tokens)
        decimals_ = uint8(bound(decimals_, 0, 18));
        initialPrice = bound(initialPrice, type(int128).min, type(int128).max);
        
        MockV3Aggregator fuzzAggregator = new MockV3Aggregator(decimals_, initialPrice);
        
        assertEq(fuzzAggregator.decimals(), decimals_);
        (, int256 price,,,) = fuzzAggregator.latestRoundData();
        assertEq(price, initialPrice);
    }
    
    // =========================
    // PRICE RANGE TESTS
    // =========================
    
    function test_extremePrices_Work() public {
        // Test very high price
        int256 highPrice = type(int128).max;
        aggregator.updateAnswer(highPrice);
        (, int256 retrievedHigh,,,) = aggregator.latestRoundData();
        assertEq(retrievedHigh, highPrice);
        
        // Test very low price
        int256 lowPrice = type(int128).min;
        aggregator.updateAnswer(lowPrice);
        (, int256 retrievedLow,,,) = aggregator.latestRoundData();
        assertEq(retrievedLow, lowPrice);
    }
    
    function test_typicalETHPrices_Work() public {
        // Test range of typical ETH prices
        int256[] memory ethPrices = new int256[](5);
        ethPrices[0] = 1000 * 1e8;  // $1,000
        ethPrices[1] = 2500 * 1e8;  // $2,500
        ethPrices[2] = 4000 * 1e8;  // $4,000
        ethPrices[3] = 500 * 1e8;   // $500
        ethPrices[4] = 10000 * 1e8; // $10,000
        
        for (uint256 i = 0; i < ethPrices.length; i++) {
            aggregator.updateAnswer(ethPrices[i]);
            
            (, int256 currentPrice,,,) = aggregator.latestRoundData();
            assertEq(currentPrice, ethPrices[i]);
            
            // Verify price is in reasonable range
            assertTrue(currentPrice >= 100 * 1e8);    // > $100
            assertTrue(currentPrice <= 20000 * 1e8);  // < $20,000
        }
    }
}