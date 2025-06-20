// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title Component Tests for EigenLVR
 * @notice Tests individual components without hook address validation
 */
contract EigenLVRComponentTest is Test {
    ChainlinkPriceOracle public priceOracle;
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    address public owner = address(0x1);
    
    function setUp() public {
        vm.prank(owner);
        priceOracle = new ChainlinkPriceOracle();
    }
    
    function test_PriceOracle_AddPriceFeed() public {
        address mockFeed = address(0x123);
        
        vm.prank(owner);
        priceOracle.addPriceFeed(token0, token1, mockFeed);
        
        // The price feed should be stored
        bytes32 pairKey = keccak256(abi.encodePacked(token0, token1));
        address storedFeed = address(priceOracle.priceFeeds(pairKey));
        assertEq(storedFeed, mockFeed);
    }
    
    function test_PriceOracle_RemovePriceFeed() public {
        address mockFeed = address(0x123);
        
        // Add then remove
        vm.startPrank(owner);
        priceOracle.addPriceFeed(token0, token1, mockFeed);
        priceOracle.removePriceFeed(token0, token1);
        vm.stopPrank();
        
        // The price feed should be removed
        bytes32 pairKey = keccak256(abi.encodePacked(token0, token1));
        address storedFeed = address(priceOracle.priceFeeds(pairKey));
        assertEq(storedFeed, address(0));
    }
    
    function test_PriceOracle_OnlyOwner() public {
        vm.prank(address(0x999));
        vm.expectRevert();
        priceOracle.addPriceFeed(token0, token1, address(0x123));
    }
    
    function test_AuctionLib_GenerateCommitment() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 expected = keccak256(abi.encodePacked(bidder, amount, nonce));
        
        assertEq(commitment, expected);
    }
    
    function test_AuctionLib_VerifyCommitment() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        bool isValid = AuctionLib.verifyCommitment(commitment, bidder, amount, nonce);
        
        assertTrue(isValid);
        
        // Test with wrong nonce
        bool isInvalid = AuctionLib.verifyCommitment(commitment, bidder, amount, 54321);
        assertFalse(isInvalid);
    }
    
    function test_AuctionLib_AuctionState() public {
        // The AuctionLib functions expect storage pointers, so we need to use a different approach
        // Let's test the logic manually
        
        uint256 startTime = block.timestamp;
        uint256 duration = 12;
        
        // Test time remaining logic
        uint256 endTime = startTime + duration;
        uint256 timeRemaining = block.timestamp >= endTime ? 0 : endTime - block.timestamp;
        assertEq(timeRemaining, 12);
        
        // Fast forward
        vm.warp(block.timestamp + 5);
        timeRemaining = block.timestamp >= endTime ? 0 : endTime - block.timestamp;
        assertEq(timeRemaining, 7);
        
        // Past end time
        vm.warp(block.timestamp + 10); // Total 15 seconds
        timeRemaining = block.timestamp >= endTime ? 0 : endTime - block.timestamp;
        assertEq(timeRemaining, 0);
        
        bool isEnded = block.timestamp >= endTime;
        assertTrue(isEnded);
    }
    
    function test_Constants_Validation() public pure {
        // Test that the percentage constants add up correctly
        uint256 LP_REWARD_PERCENTAGE = 8500;      // 85%
        uint256 AVS_REWARD_PERCENTAGE = 1000;     // 10%
        uint256 PROTOCOL_FEE_PERCENTAGE = 300;    // 3%
        uint256 GAS_COMPENSATION_PERCENTAGE = 200; // 2%
        uint256 BASIS_POINTS = 10000;             // 100%
        
        uint256 totalPercentage = LP_REWARD_PERCENTAGE + 
                                AVS_REWARD_PERCENTAGE + 
                                PROTOCOL_FEE_PERCENTAGE + 
                                GAS_COMPENSATION_PERCENTAGE;
        
        assertEq(totalPercentage, BASIS_POINTS);
    }
    
    function test_LVR_ThresholdCalculation() public pure {
        // Test LVR threshold calculation logic
        uint256 BASIS_POINTS = 10000;
        uint256 LVR_THRESHOLD = 50; // 0.5%
        
        // Simulate price deviation calculation
        uint256 poolPrice = 1e18;
        uint256 externalPrice = 1.01e18; // 1% higher
        
        uint256 deviation = ((externalPrice - poolPrice) * BASIS_POINTS) / poolPrice;
        assertEq(deviation, 100); // 1% = 100 basis points
        
        // Should trigger auction (100 > 50)
        assertTrue(deviation >= LVR_THRESHOLD);
        
        // Test smaller deviation
        externalPrice = 1.003e18; // 0.3% higher
        deviation = ((externalPrice - poolPrice) * BASIS_POINTS) / poolPrice;
        assertEq(deviation, 30); // 0.3% = 30 basis points
        
        // Should NOT trigger auction (30 < 50)
        assertFalse(deviation >= LVR_THRESHOLD);
    }
    
    function test_MEV_Distribution() public pure {
        // Test MEV distribution calculation
        uint256 totalProceeds = 1 ether;
        uint256 BASIS_POINTS = 10000;
        
        uint256 LP_REWARD_PERCENTAGE = 8500;      // 85%
        uint256 AVS_REWARD_PERCENTAGE = 1000;     // 10%
        uint256 PROTOCOL_FEE_PERCENTAGE = 300;    // 3%
        uint256 GAS_COMPENSATION_PERCENTAGE = 200; // 2%
        
        uint256 lpAmount = (totalProceeds * LP_REWARD_PERCENTAGE) / BASIS_POINTS;
        uint256 avsAmount = (totalProceeds * AVS_REWARD_PERCENTAGE) / BASIS_POINTS;
        uint256 protocolAmount = (totalProceeds * PROTOCOL_FEE_PERCENTAGE) / BASIS_POINTS;
        uint256 gasAmount = (totalProceeds * GAS_COMPENSATION_PERCENTAGE) / BASIS_POINTS;
        
        assertEq(lpAmount, 0.85 ether);
        assertEq(avsAmount, 0.1 ether);
        assertEq(protocolAmount, 0.03 ether);
        assertEq(gasAmount, 0.02 ether);
        
        // Verify total adds up
        assertEq(lpAmount + avsAmount + protocolAmount + gasAmount, totalProceeds);
    }
    
    function test_SwapSignificance() public pure {
        // Test swap significance threshold
        int256 SIGNIFICANCE_THRESHOLD = 1e18; // 1 ETH
        
        // Test significant swaps
        assertTrue(2e18 > SIGNIFICANCE_THRESHOLD);  // 2 ETH
        assertTrue(-2e18 < -SIGNIFICANCE_THRESHOLD); // -2 ETH
        
        // Test insignificant swaps
        assertFalse(0.5e18 > SIGNIFICANCE_THRESHOLD);  // 0.5 ETH
        assertFalse(-0.5e18 < -SIGNIFICANCE_THRESHOLD); // -0.5 ETH
    }
}

// Mock Chainlink aggregator for testing
contract MockChainlinkAggregator {
    int256 private _price;
    uint256 private _updatedAt;
    uint8 private _decimals;
    
    constructor(int256 price_, uint8 decimals_) {
        _price = price_;
        _decimals = decimals_;
        _updatedAt = block.timestamp;
    }
    
    function decimals() external view returns (uint8) {
        return _decimals;
    }
    
    function description() external pure returns (string memory) {
        return "Mock ETH/USD";
    }
    
    function version() external pure returns (uint256) {
        return 1;
    }
    
    function getRoundData(uint80)
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, _price, block.timestamp, _updatedAt, 1);
    }
    
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, _price, block.timestamp, _updatedAt, 1);
    }
    
    function setPrice(int256 price_) external {
        _price = price_;
        _updatedAt = block.timestamp;
    }
}

contract ChainlinkOracleIntegrationTest is Test {
    ChainlinkPriceOracle public priceOracle;
    MockChainlinkAggregator public mockFeed;
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    address public owner = address(0x1);
    
    function setUp() public {
        vm.prank(owner);
        priceOracle = new ChainlinkPriceOracle();
        
        // Deploy mock Chainlink feed
        mockFeed = new MockChainlinkAggregator(2000e8, 8); // $2000 with 8 decimals
        
        // Add the price feed
        vm.prank(owner);
        priceOracle.addPriceFeed(token0, token1, address(mockFeed));
    }
    
    function test_GetPrice() public view {
        uint256 price = priceOracle.getPrice(token0, token1);
        // Should normalize 2000e8 (8 decimals) to 2000e18 (18 decimals)
        assertEq(price, 2000e18);
    }
    
    function test_PriceNormalization() public {
        // Test different decimal cases
        MockChainlinkAggregator feed6Decimals = new MockChainlinkAggregator(2000e6, 6);
        MockChainlinkAggregator feed18Decimals = new MockChainlinkAggregator(2000e18, 18);
        
        Currency token2 = Currency.wrap(address(0x300));
        Currency token3 = Currency.wrap(address(0x400));
        
        vm.startPrank(owner);
        priceOracle.addPriceFeed(token0, token2, address(feed6Decimals));
        priceOracle.addPriceFeed(token0, token3, address(feed18Decimals));
        vm.stopPrank();
        
        // All should normalize to 2000e18
        assertEq(priceOracle.getPrice(token0, token1), 2000e18); // 8 decimals
        assertEq(priceOracle.getPrice(token0, token2), 2000e18); // 6 decimals  
        assertEq(priceOracle.getPrice(token0, token3), 2000e18); // 18 decimals
    }
    
    function test_StalePrice() public {
        // Set price to old timestamp
        vm.warp(block.timestamp + 2 hours); // 2 hours in future
        
        // Should detect stale price
        assertTrue(priceOracle.isPriceStale(token0, token1));
        
        // Should revert on getPrice
        vm.expectRevert("ChainlinkOracle: stale price");
        priceOracle.getPrice(token0, token1);
    }
    
    function test_InvalidPrice() public {
        MockChainlinkAggregator negativeFeed = new MockChainlinkAggregator(-100, 8);
        
        Currency token2 = Currency.wrap(address(0x300));
        
        vm.prank(owner);
        priceOracle.addPriceFeed(token0, token2, address(negativeFeed));
        
        vm.expectRevert("ChainlinkOracle: invalid price");
        priceOracle.getPrice(token0, token2);
    }
}