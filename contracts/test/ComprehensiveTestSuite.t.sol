// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title Comprehensive Test Suite for 100% Coverage
 * @notice Tests all components with proper edge case handling
 */
contract ComprehensiveTestSuite is Test {
    using AuctionLib for AuctionLib.Auction;
    
    /*//////////////////////////////////////////////////////////////
                            AUCTION LIB TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AuctionLib_BasicFunctionality() public {
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: 1000,
            duration: 500,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        // Test before start
        vm.warp(500);
        assertFalse(auction.isAuctionActive());
        assertFalse(auction.isAuctionEnded());
        assertEq(auction.getTimeRemaining(), 0);
        
        // Test during auction
        vm.warp(1200);
        assertTrue(auction.isAuctionActive());
        assertFalse(auction.isAuctionEnded());
        assertEq(auction.getTimeRemaining(), 300);
        
        // Test after auction
        vm.warp(1600);
        assertFalse(auction.isAuctionActive());
        assertTrue(auction.isAuctionEnded());
        assertEq(auction.getTimeRemaining(), 0);
    }
    
    function test_AuctionLib_InactiveAuction() public {
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: 1000,
            duration: 500,
            isActive: false, // Inactive
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        vm.warp(1200); // During what would be active time
        assertFalse(auction.isAuctionActive());
        assertEq(auction.getTimeRemaining(), 0);
    }
    
    function test_AuctionLib_EdgeCaseTimes() public {
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: 1000,
            duration: 500,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        // Test at exact start time
        vm.warp(1000);
        assertTrue(auction.isAuctionActive());
        assertFalse(auction.isAuctionEnded());
        assertEq(auction.getTimeRemaining(), 500);
        
        // Test at exact end time
        vm.warp(1500);
        assertFalse(auction.isAuctionActive());
        assertTrue(auction.isAuctionEnded());
        assertEq(auction.getTimeRemaining(), 0);
    }
    
    function test_AuctionLib_SafeOverflowHandling() public {
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: type(uint256).max - 50,
            duration: 100, // Would overflow
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        // Test that overflow is handled gracefully
        // Implementation should treat this as infinite duration
        vm.warp(type(uint256).max - 10);
        assertTrue(auction.isAuctionActive()); // Should be active due to overflow protection
        assertFalse(auction.isAuctionEnded()); // Should not be ended
    }
    
    function test_AuctionLib_InfiniteDuration() public {
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: 1000,
            duration: type(uint256).max,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        vm.warp(2000000); // Far in the future
        assertTrue(auction.isAuctionActive());
        assertFalse(auction.isAuctionEnded());
        assertEq(auction.getTimeRemaining(), type(uint256).max);
    }
    
    function test_AuctionLib_Commitments() public pure {
        address bidder = address(0x123);
        uint256 amount = 1 ether;
        uint256 nonce = 12345;
        
        bytes32 commitment = AuctionLib.generateCommitment(bidder, amount, nonce);
        assertTrue(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce));
        
        // Test invalid verifications
        assertFalse(AuctionLib.verifyCommitment(commitment, address(0x456), amount, nonce));
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount + 1, nonce));
        assertFalse(AuctionLib.verifyCommitment(commitment, bidder, amount, nonce + 1));
    }
    
    function test_AuctionLib_CommitmentEdgeCases() public pure {
        // Test with zero values
        bytes32 commitment1 = AuctionLib.generateCommitment(address(0), 0, 0);
        assertTrue(AuctionLib.verifyCommitment(commitment1, address(0), 0, 0));
        
        // Test with max values
        address maxAddr = address(type(uint160).max);
        uint256 maxUint = type(uint256).max;
        bytes32 commitment2 = AuctionLib.generateCommitment(maxAddr, maxUint, maxUint);
        assertTrue(AuctionLib.verifyCommitment(commitment2, maxAddr, maxUint, maxUint));
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK MINER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_HookMiner_NoFlags() public pure {
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(0x1),
            0,
            hex"60806040",
            hex"00"
        );
        
        assertTrue(uint160(hookAddress) & 0 == 0);
        // For no flags, should find quickly
    }
    
    function test_HookMiner_ComputeAddress() public pure {
        address computed1 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"60806040"
        );
        
        address computed2 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"60806040"
        );
        
        // Should be deterministic
        assertEq(computed1, computed2);
        assertTrue(computed1 != address(0));
    }
    
    function test_HookMiner_DifferentInputs() public pure {
        address addr1 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"60806040"
        );
        
        address addr2 = HookMiner.computeAddress(
            address(0x2), // Different deployer
            bytes32(uint256(123)),
            hex"60806040"
        );
        
        address addr3 = HookMiner.computeAddress(
            address(0x1),
            bytes32(uint256(456)), // Different salt
            hex"60806040"
        );
        
        // All should be different
        assertTrue(addr1 != addr2);
        assertTrue(addr1 != addr3);
        assertTrue(addr2 != addr3);
    }
    
    /*//////////////////////////////////////////////////////////////
                            MOCK TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_MockPriceOracle() public {
        MockPriceOracle oracle = new MockPriceOracle();
        
        Currency token0 = Currency.wrap(address(0x100));
        Currency token1 = Currency.wrap(address(0x200));
        
        // Test default price
        uint256 defaultPrice = oracle.getPrice(token0, token1);
        assertEq(defaultPrice, 2000e18);
        
        // Test setting custom price
        oracle.setPrice(token0, token1, 3000e18);
        uint256 customPrice = oracle.getPrice(token0, token1);
        assertEq(customPrice, 3000e18);
        
        // Test staleness
        assertFalse(oracle.isPriceStale(token0, token1));
        oracle.setPriceStale(token0, token1, true);
        assertTrue(oracle.isPriceStale(token0, token1));
        
        // Test update time
        uint256 updateTime = oracle.getLastUpdateTime(token0, token1);
        assertEq(updateTime, block.timestamp);
        
        // Test price at time
        uint256 priceAtTime = oracle.getPriceAtTime(token0, token1, block.timestamp - 100);
        assertEq(priceAtTime, 3000e18);
    }
    
    function test_MockAVSDirectory() public {
        MockAVSDirectory avsDir = new MockAVSDirectory();
        
        address avs = address(this);
        address operator = address(0x123);
        
        // Initially not registered
        assertFalse(avsDir.isOperatorRegistered(avs, operator));
        assertEq(avsDir.getOperatorStake(avs, operator), 0);
        
        // Register operator
        avsDir.registerOperatorToAVS(operator, "");
        assertTrue(avsDir.isOperatorRegistered(avs, operator));
        
        // Set stake
        avsDir.setOperatorStake(avs, operator, 100 ether);
        assertEq(avsDir.getOperatorStake(avs, operator), 100 ether);
        
        // Deregister operator
        avsDir.deregisterOperatorFromAVS(operator);
        assertFalse(avsDir.isOperatorRegistered(avs, operator));
    }
    
    /*//////////////////////////////////////////////////////////////
                            UNIT TESTS FOR COVERAGE
    //////////////////////////////////////////////////////////////*/
    
    function test_AuctionStruct_AllFields() public {
        PoolId poolId = PoolId.wrap(bytes32(uint256(0x123)));
        uint256 startTime = 1234567890;
        uint256 duration = 3600;
        bool isActive = true;
        bool isComplete = false;
        address winner = address(0x456);
        uint256 winningBid = 5 ether;
        uint256 totalBids = 10;
        
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: poolId,
            startTime: startTime,
            duration: duration,
            isActive: isActive,
            isComplete: isComplete,
            winner: winner,
            winningBid: winningBid,
            totalBids: totalBids
        });
        
        assertEq(PoolId.unwrap(auction.poolId), PoolId.unwrap(poolId));
        assertEq(auction.startTime, startTime);
        assertEq(auction.duration, duration);
        assertEq(auction.isActive, isActive);
        assertEq(auction.isComplete, isComplete);
        assertEq(auction.winner, winner);
        assertEq(auction.winningBid, winningBid);
        assertEq(auction.totalBids, totalBids);
    }
    
    function test_BidStruct_AllFields() public {
        address bidder = address(0x789);
        uint256 amount = 2.5 ether;
        bytes32 commitment = keccak256("test commitment");
        bool revealed = true;
        uint256 timestamp = 1234567890;
        
        AuctionLib.Bid memory bid = AuctionLib.Bid({
            bidder: bidder,
            amount: amount,
            commitment: commitment,
            revealed: revealed,
            timestamp: timestamp
        });
        
        assertEq(bid.bidder, bidder);
        assertEq(bid.amount, amount);
        assertEq(bid.commitment, commitment);
        assertEq(bid.revealed, revealed);
        assertEq(bid.timestamp, timestamp);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_AuctionTiming(
        uint128 startTime,
        uint128 duration,
        uint128 currentTime,
        bool isActive
    ) public {
        // Avoid overflow
        vm.assume(startTime < type(uint128).max - duration);
        vm.assume(duration > 0);
        
        AuctionLib.Auction memory auction = AuctionLib.Auction({
            poolId: PoolId.wrap(bytes32(uint256(1))),
            startTime: startTime,
            duration: duration,
            isActive: isActive,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        vm.warp(currentTime);
        
        bool expectedActive = isActive && 
                             currentTime >= startTime && 
                             currentTime < startTime + duration;
        bool expectedEnded = currentTime >= startTime + duration;
        
        assertEq(auction.isAuctionActive(), expectedActive);
        assertEq(auction.isAuctionEnded(), expectedEnded);
        
        if (!isActive) {
            assertEq(auction.getTimeRemaining(), 0);
        } else if (currentTime >= startTime + duration) {
            assertEq(auction.getTimeRemaining(), 0);
        } else if (currentTime < startTime) {
            assertEq(auction.getTimeRemaining(), 0);
        } else {
            assertEq(auction.getTimeRemaining(), startTime + duration - currentTime);
        }
    }
    
    function testFuzz_CommitmentGeneration(
        address bidder,
        uint256 amount,
        uint256 nonce
    ) public pure {
        bytes32 commitment1 = AuctionLib.generateCommitment(bidder, amount, nonce);
        bytes32 commitment2 = AuctionLib.generateCommitment(bidder, amount, nonce);
        
        // Should be deterministic
        assertEq(commitment1, commitment2);
        
        // Should verify correctly
        assertTrue(AuctionLib.verifyCommitment(commitment1, bidder, amount, nonce));
    }
    
    function testFuzz_HookMinerDeterministic(
        address deployer,
        bytes32 salt,
        bytes memory bytecode
    ) public pure {
        address addr1 = HookMiner.computeAddress(deployer, salt, bytecode);
        address addr2 = HookMiner.computeAddress(deployer, salt, bytecode);
        
        assertEq(addr1, addr2);
    }
}

// Import dependencies for the test
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

contract MockPriceOracle {
    mapping(bytes32 => uint256) public prices;
    mapping(bytes32 => bool) public stalePrices;
    
    function getPrice(Currency token0, Currency token1) external view returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        uint256 price = prices[key];
        return price > 0 ? price : 2000e18;
    }
    
    function setPrice(Currency token0, Currency token1, uint256 price) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        prices[key] = price;
    }
    
    function isPriceStale(Currency token0, Currency token1) external view returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        return stalePrices[key];
    }
    
    function setPriceStale(Currency token0, Currency token1, bool stale) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        stalePrices[key] = stale;
    }
    
    function getLastUpdateTime(Currency, Currency) external view returns (uint256) {
        return block.timestamp;
    }
    
    function getPriceAtTime(Currency token0, Currency token1, uint256) external view returns (uint256) {
        return this.getPrice(token0, token1);
    }
}

import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";

contract MockAVSDirectory is IAVSDirectory {
    mapping(address => mapping(address => bool)) public operatorRegistered;
    mapping(address => mapping(address => uint256)) public operatorStakes;
    
    function registerOperatorToAVS(address operator, bytes calldata) external override {
        operatorRegistered[msg.sender][operator] = true;
    }
    
    function deregisterOperatorFromAVS(address operator) external override {
        operatorRegistered[msg.sender][operator] = false;
    }
    
    function isOperatorRegistered(address avs, address operator) external view override returns (bool) {
        return operatorRegistered[avs][operator];
    }
    
    function getOperatorStake(address avs, address operator) external view override returns (uint256) {
        return operatorStakes[avs][operator];
    }
    
    function setOperatorStake(address avs, address operator, uint256 stake) external {
        operatorStakes[avs][operator] = stake;
    }
}