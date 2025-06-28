// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AuctionLibFixed} from "../src/libraries/AuctionLibFixed.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

/**
 * @title Fixed AuctionLib Tests
 * @notice Tests the fixed version of AuctionLib with proper overflow handling
 */
contract AuctionLibFixedTest is Test {
    using AuctionLibFixed for AuctionLibFixed.Auction;
    
    AuctionLibFixed.Auction internal testAuction;
    
    function setUp() public {
        testAuction = AuctionLibFixed.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: block.timestamp,
            duration: 60,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
    }
    
    /*//////////////////////////////////////////////////////////////
                    FIXED AUCTION ACTIVE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_IsAuctionActive_InfiniteDuration_BeforeStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp + 100; // Future start
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Not started yet, even with infinite duration
    }
    
    function test_IsAuctionActive_InfiniteDuration_AfterStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp - 100; // Past start
        
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive); // Should be active with infinite duration
    }
    
    function test_IsAuctionActive_InfiniteDuration_AtStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp; // Exact start time
        
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive); // Should be active at exact start time
    }
    
    function test_IsAuctionActive_OverflowSafeEndTime_Active() public {
        // Set up conditions where startTime + duration would overflow
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100; // This would overflow
        
        // Should be active due to overflow protection
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive);
    }
    
    function test_IsAuctionActive_OverflowSafeEndTime_BeforeStart() public {
        // Set up overflow condition but before start time
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100;
        
        // Move to before start time
        vm.warp(type(uint256).max - 100);
        
        bool isActive = testAuction.isAuctionActive();
        assertFalse(isActive); // Before start time
    }
    
    function test_IsAuctionActive_ExactOverflowBoundary() public {
        // Test exact overflow boundary
        testAuction.startTime = type(uint256).max - 10;
        testAuction.duration = 11; // Exactly overflow
        
        bool isActive = testAuction.isAuctionActive();
        assertTrue(isActive); // Should treat as infinite duration
    }
    
    /*//////////////////////////////////////////////////////////////
                    FIXED TIME REMAINING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetTimeRemaining_InfiniteDuration_BeforeStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp + 100;
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0); // Not started yet
    }
    
    function test_GetTimeRemaining_InfiniteDuration_AfterStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp - 100;
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max); // Infinite time remaining
    }
    
    function test_GetTimeRemaining_InfiniteDuration_AtStart() public {
        testAuction.duration = type(uint256).max;
        testAuction.startTime = block.timestamp;
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max); // Infinite time remaining
    }
    
    function test_GetTimeRemaining_OverflowSafe_BeforeStart() public {
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100;
        
        // Move to before start
        vm.warp(type(uint256).max - 100);
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0); // Not started
    }
    
    function test_GetTimeRemaining_OverflowSafe_AfterStart() public {
        testAuction.startTime = type(uint256).max - 50;
        testAuction.duration = 100;
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max); // Treated as infinite
    }
    
    function test_GetTimeRemaining_ExactOverflowBoundary() public {
        testAuction.startTime = type(uint256).max - 10;
        testAuction.duration = 11;
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, type(uint256).max); // Overflow, treated as infinite
    }
    
    function test_GetTimeRemaining_NoOverflow_PartialTime() public {
        testAuction.startTime = 1000;
        testAuction.duration = 500;
        
        vm.warp(1200); // 200 seconds in, 300 remaining
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 300);
    }
    
    function test_GetTimeRemaining_NoOverflow_AtEnd() public {
        testAuction.startTime = 1000;
        testAuction.duration = 500;
        
        vm.warp(1500); // Exactly at end
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    function test_GetTimeRemaining_NoOverflow_PastEnd() public {
        testAuction.startTime = 1000;
        testAuction.duration = 500;
        
        vm.warp(1600); // Past end
        
        uint256 timeRemaining = testAuction.getTimeRemaining();
        assertEq(timeRemaining, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                    BRANCH COVERAGE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_IsAuctionActive_AllConditions() public {
        // Test the && condition branches
        
        // Case 1: isActive = false (first condition fails)
        testAuction.isActive = false;
        testAuction.startTime = block.timestamp;
        testAuction.duration = 100;
        
        assertFalse(testAuction.isAuctionActive());
        
        // Case 2: isActive = true, before start (second condition fails)
        testAuction.isActive = true;
        testAuction.startTime = block.timestamp + 100;
        testAuction.duration = 100;
        
        assertFalse(testAuction.isAuctionActive());
        
        // Case 3: isActive = true, after end (third condition fails)
        testAuction.isActive = true;
        testAuction.startTime = block.timestamp - 200;
        testAuction.duration = 100;
        
        assertFalse(testAuction.isAuctionActive());
        
        // Case 4: All conditions true
        testAuction.isActive = true;
        testAuction.startTime = block.timestamp - 50;
        testAuction.duration = 100;
        
        assertTrue(testAuction.isAuctionActive());
    }
    
    /*//////////////////////////////////////////////////////////////
                    COMMITMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GenerateCommitment_AllZeros() public pure {
        bytes32 commitment = AuctionLibFixed.generateCommitment(address(0), 0, 0);
        bytes32 expected = keccak256(abi.encodePacked(address(0), uint256(0), uint256(0)));
        assertEq(commitment, expected);
    }
    
    function test_GenerateCommitment_MaxValues() public pure {
        address maxAddr = address(type(uint160).max);
        uint256 maxUint = type(uint256).max;
        
        bytes32 commitment = AuctionLibFixed.generateCommitment(maxAddr, maxUint, maxUint);
        bytes32 expected = keccak256(abi.encodePacked(maxAddr, maxUint, maxUint));
        assertEq(commitment, expected);
    }
    
    function test_VerifyCommitment_Valid() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLibFixed.generateCommitment(bidder, amount, nonce);
        assertTrue(AuctionLibFixed.verifyCommitment(commitment, bidder, amount, nonce));
    }
    
    function test_VerifyCommitment_Invalid() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLibFixed.generateCommitment(bidder, amount, nonce);
        
        // Invalid parameters should fail
        assertFalse(AuctionLibFixed.verifyCommitment(commitment, address(0x456), amount, nonce));
        assertFalse(AuctionLibFixed.verifyCommitment(commitment, bidder, amount + 1, nonce));
        assertFalse(AuctionLibFixed.verifyCommitment(commitment, bidder, amount, nonce + 1));
    }
    
    /*//////////////////////////////////////////////////////////////
                    FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_IsAuctionActive_RandomTimes(
        uint128 startTime,
        uint128 duration,
        uint128 currentTime,
        bool isActive
    ) public {
        // Avoid overflow conditions for this fuzz test
        vm.assume(startTime < type(uint128).max - duration);
        vm.assume(duration > 0);
        
        testAuction.startTime = startTime;
        testAuction.duration = duration;
        testAuction.isActive = isActive;
        
        vm.warp(currentTime);
        
        bool expected = isActive && 
                       currentTime >= startTime && 
                       currentTime < startTime + duration;
        
        assertEq(testAuction.isAuctionActive(), expected);
    }
    
    function testFuzz_CommitmentGeneration(
        address bidder,
        uint256 amount,
        uint256 nonce
    ) public pure {
        bytes32 commitment1 = AuctionLibFixed.generateCommitment(bidder, amount, nonce);
        bytes32 commitment2 = AuctionLibFixed.generateCommitment(bidder, amount, nonce);
        
        // Should be deterministic
        assertEq(commitment1, commitment2);
        
        // Should verify correctly
        assertTrue(AuctionLibFixed.verifyCommitment(commitment1, bidder, amount, nonce));
    }
}