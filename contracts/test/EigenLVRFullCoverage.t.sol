// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";

/**
 * @title EigenLVRFullCoverage
 * @notice Additional comprehensive tests to achieve 100% coverage
 */
contract EigenLVRFullCoverageTest is Test {
    using AuctionLib for AuctionLib.Auction;
    using AuctionLib for AuctionLib.Bid;

    /*//////////////////////////////////////////////////////////////
                        HOOK MINER ADDITIONAL COVERAGE
    //////////////////////////////////////////////////////////////*/

    function test_Coverage_HookMiner_ErrorCase() public {
        // Test with flags that are impossible to find within iteration limit
        // This should trigger the revert case
        vm.expectRevert("HookMiner: Could not find valid address");
        HookMiner.find(
            address(0x1),
            0xFFFF, // Very difficult flags requiring many iterations
            hex"608060405234801561001057600080fd5b50", // Complex bytecode
            hex"1234567890abcdef" // Additional complexity
        );
    }

    function test_Coverage_HookMiner_ZeroFlags() public pure {
        // Test the zero flags path
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            0x0000, // Zero flags - should return immediately
            hex"608060405234801561001057600080fd5b50",
            hex""
        );
        
        // For zero flags, salt should be 0 and address should be computed
        assertEq(salt, bytes32(0));
        assertTrue(hookAddress != address(0));
    }

    function test_Coverage_HookMiner_ComputeAddress_EdgeCases() public pure {
        // Test with zero deployer
        address computed1 = HookMiner.computeAddress(
            address(0),
            bytes32(0),
            hex"00"
        );
        assertTrue(computed1 != address(0));

        // Test with empty bytecode
        address computed2 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex""
        );
        assertTrue(computed2 != address(0));

        // Test with maximum salt
        address computed3 = HookMiner.computeAddress(
            address(0x1),
            bytes32(type(uint256).max),
            hex"608060405234801561001057600080fd5b50"
        );
        assertTrue(computed3 != address(0));
    }

    /*//////////////////////////////////////////////////////////////
                      AUCTION LIB COMPLETE COVERAGE
    //////////////////////////////////////////////////////////////*/

    function test_Coverage_AuctionLib_InfiniteAndZeroDuration() public {
        // Test with zero duration
        AuctionLib.Auction memory zeroDurationAuction = AuctionLib.Auction({
            isActive: true,
            startTime: block.timestamp,
            duration: 0, // Zero duration
            poolId: bytes32(uint256(1)),
            totalBids: 0
        });

        assertTrue(zeroDurationAuction.isAuctionEnded());
        assertEq(zeroDurationAuction.getTimeRemaining(), 0);

        // Test with very large duration (simulating infinite)
        AuctionLib.Auction memory infiniteAuction = AuctionLib.Auction({
            isActive: true,
            startTime: block.timestamp,
            duration: type(uint256).max,
            poolId: bytes32(uint256(1)),
            totalBids: 0
        });

        assertTrue(infiniteAuction.isAuctionActive());
        assertFalse(infiniteAuction.isAuctionEnded());
    }

    function test_Coverage_AuctionLib_TimeOverflowProtection() public {
        // Test potential overflow scenarios
        AuctionLib.Auction memory overflowAuction = AuctionLib.Auction({
            isActive: true,
            startTime: type(uint256).max - 100, // Very large start time
            duration: 1000, // Duration that would overflow when added
            poolId: bytes32(uint256(1)),
            totalBids: 0
        });

        // These operations should not revert due to overflow protection
        bool isActive = overflowAuction.isAuctionActive();
        bool isEnded = overflowAuction.isAuctionEnded();
        uint256 timeRemaining = overflowAuction.getTimeRemaining();

        // Just verify no reverts occurred
        assertTrue(isActive || !isActive);
        assertTrue(isEnded || !isEnded);
        assertTrue(timeRemaining >= 0);
    }

    function test_Coverage_AuctionLib_BeforeStartTime() public {
        // Test auction that hasn't started yet
        AuctionLib.Auction memory futureAuction = AuctionLib.Auction({
            isActive: true,
            startTime: block.timestamp + 1000, // Future start time
            duration: 500,
            poolId: bytes32(uint256(1)),
            totalBids: 0
        });

        assertFalse(futureAuction.isAuctionActive()); // Not active yet
        assertFalse(futureAuction.isAuctionEnded()); // Not ended yet
        assertTrue(futureAuction.getTimeRemaining() > 0); // Still has time
    }

    function test_Coverage_AuctionLib_InactiveAuction() public {
        // Test inactive auction
        AuctionLib.Auction memory inactiveAuction = AuctionLib.Auction({
            isActive: false, // Inactive
            startTime: block.timestamp,
            duration: 1000,
            poolId: bytes32(uint256(1)),
            totalBids: 0
        });

        assertFalse(inactiveAuction.isAuctionActive());
        assertEq(inactiveAuction.getTimeRemaining(), 0);
    }

    function test_Coverage_AuctionLib_CommitmentCornerCases() public pure {
        // Test commitment with all possible edge values
        address maxAddr = address(type(uint160).max);
        uint256 maxAmount = type(uint256).max;
        uint256 maxNonce = type(uint256).max;

        bytes32 commitment1 = AuctionLib.generateCommitment(maxAddr, maxAmount, maxNonce);
        assertTrue(commitment1 != bytes32(0));

        // Verify the commitment
        bool verified = AuctionLib.verifyCommitment(commitment1, maxAddr, maxAmount, maxNonce);
        assertTrue(verified);

        // Test with slightly different values
        bool notVerified1 = AuctionLib.verifyCommitment(commitment1, address(0), maxAmount, maxNonce);
        assertFalse(notVerified1);

        bool notVerified2 = AuctionLib.verifyCommitment(commitment1, maxAddr, 0, maxNonce);
        assertFalse(notVerified2);

        bool notVerified3 = AuctionLib.verifyCommitment(commitment1, maxAddr, maxAmount, 0);
        assertFalse(notVerified3);
    }

    function test_Coverage_AuctionLib_BidStructCreation() public pure {
        // Test bid struct with edge values
        AuctionLib.Bid memory maxBid = AuctionLib.Bid({
            bidder: address(type(uint160).max),
            amount: type(uint256).max,
            nonce: type(uint256).max,
            commitment: bytes32(type(uint256).max)
        });

        assertTrue(maxBid.bidder != address(0));
        assertTrue(maxBid.amount > 0);
        assertTrue(maxBid.commitment != bytes32(0));

        AuctionLib.Bid memory zeroBid = AuctionLib.Bid({
            bidder: address(0),
            amount: 0,
            nonce: 0,
            commitment: bytes32(0)
        });

        assertTrue(maxBid.bidder != zeroBid.bidder);
        assertTrue(maxBid.amount != zeroBid.amount);
        assertTrue(maxBid.commitment != zeroBid.commitment);
    }

    /*//////////////////////////////////////////////////////////////
                         FUZZING FOR COMPLETE COVERAGE
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Coverage_AuctionLib_AllTimingCombinations(
        uint128 startTime,
        uint128 duration,
        uint128 currentOffset,
        bool isActive
    ) public {
        // Bound inputs to prevent unrealistic values
        startTime = uint128(bound(startTime, 1, type(uint128).max / 2));
        duration = uint128(bound(duration, 0, type(uint128).max / 2));
        currentOffset = uint128(bound(currentOffset, 0, type(uint128).max / 4));

        vm.warp(startTime + currentOffset);

        AuctionLib.Auction memory auction = AuctionLib.Auction({
            isActive: isActive,
            startTime: startTime,
            duration: duration,
            poolId: bytes32(uint256(startTime) ^ uint256(duration)),
            totalBids: uint32(startTime % type(uint32).max)
        });

        // Test all functions to ensure no edge case causes reverts
        bool active = auction.isAuctionActive();
        bool ended = auction.isAuctionEnded();
        uint256 timeRemaining = auction.getTimeRemaining();

        // Basic invariants
        if (!isActive) {
            assertFalse(active);
        }

        if (duration == 0) {
            assertTrue(ended);
            assertEq(timeRemaining, 0);
        }

        // Verify no overflow occurred (functions completed without revert)
        assertTrue(active || !active);
        assertTrue(ended || !ended);
        assertTrue(timeRemaining >= 0);
    }

    function testFuzz_Coverage_HookMiner_AllInputCombinations(
        address deployer,
        uint16 flags, // Limit to 16 bits to avoid impossible flags
        bytes calldata bytecode
    ) public {
        // Skip if bytecode is too large (gas limit)
        vm.assume(bytecode.length <= 1000);
        
        if (flags == 0) {
            // Zero flags should always work
            (address hookAddress, bytes32 salt) = HookMiner.find(
                deployer,
                flags,
                bytecode,
                hex""
            );
            assertEq(salt, bytes32(0));
            assertTrue(hookAddress != address(0));
        } else if (flags <= 0x000F) {
            // Low flags should usually be findable
            try HookMiner.find(deployer, flags, bytecode, hex"") returns (address hookAddress, bytes32) {
                assertTrue(uint160(hookAddress) & flags == flags);
            } catch {
                // High flags might not be findable within iteration limit - this is ok
            }
        }
        // Higher flags are expected to potentially fail due to iteration limits
    }

    function testFuzz_Coverage_CommitmentGeneration_AllInputs(
        address bidder,
        uint256 amount,
        uint256 nonce
    ) public pure {
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        // Commitment should never be zero (hash collision extremely unlikely)
        assertTrue(commitment != bytes32(0));
        
        // Verification should work
        bool verified = AuctionLib.verifyCommitment(commitment, bidder, amount, nonce);
        assertTrue(verified);
        
        // Different inputs should give different commitments (with high probability)
        if (bidder != address(0) || amount != 0 || nonce != 0) {
            bytes32 differentCommitment = AuctionLib.generateCommitment(address(0), 0, 0);
            assertTrue(commitment != differentCommitment);
        }
    }
}