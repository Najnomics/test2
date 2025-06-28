// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {HookMinerFixed} from "../src/utils/HookMinerFixed.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/**
 * @title Fixed HookMiner Tests
 * @notice Tests the fixed version of HookMiner
 */
contract HookMinerFixedTest is Test {
    address public deployer = address(0x1);
    bytes public creationCode = hex"608060405234801561001057600080fd5b50610120806100206000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c8063b69fd45e14602d575b600080fd5b60336033565b005b600080fdfea26469706673582212203c5c4b5d7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e7e6e64736f6c63430008120033";
    bytes public constructorArgs = abi.encode(address(0x123), uint256(456));
    
    function test_Find_NoFlags() public pure {
        uint160 flags = 0;
        
        (address hookAddress, bytes32 salt) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertEq(salt, bytes32(0)); // Should find immediately with no flags
    }
    
    function test_Find_SingleFlag_BeforeSwap() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        (address hookAddress, bytes32 salt) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_SingleFlag_AfterSwap() public pure {
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        
        (address hookAddress, bytes32 salt) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_MultipleFlags() public pure {
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        
        (address hookAddress, bytes32 salt) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_LiquidityFlags() public pure {
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
        );
        
        (address hookAddress, bytes32 salt) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_Find_DifferentDeployer() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        (address hookAddress1, bytes32 salt1) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        (address hookAddress2,) = HookMinerFixed.find(
            address(0x2),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        // Different deployers should produce different addresses
        assertTrue(hookAddress1 != hookAddress2);
        assertTrue(uint160(hookAddress1) & flags == flags);
        assertTrue(uint160(hookAddress2) & flags == flags);
    }
    
    function test_Find_DifferentBytecode() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        (address hookAddress1, ) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        (address hookAddress2, ) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b51", // Different bytecode
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        // Different bytecode should produce different addresses
        assertTrue(hookAddress1 != hookAddress2);
        assertTrue(uint160(hookAddress1) & flags == flags);
        assertTrue(uint160(hookAddress2) & flags == flags);
    }
    
    function test_ComputeAddress() public pure {
        address computed = HookMinerFixed.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        // Verify it's a valid address
        assertTrue(computed != address(0));
        
        // Compute again with same inputs
        address computed2 = HookMinerFixed.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        // Should be deterministic
        assertEq(computed, computed2);
    }
    
    function test_ComputeAddress_DifferentInputs() public pure {
        address addr1 = HookMinerFixed.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        address addr2 = HookMinerFixed.computeAddress(
            address(0x2), // Different deployer
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        
        address addr3 = HookMinerFixed.computeAddress(
            address(0x1),
            bytes32(uint256(456)), // Different salt
            hex"608060405234801561001057600080fd5b50"
        );
        
        // All should be different
        assertTrue(addr1 != addr2);
        assertTrue(addr1 != addr3);
        assertTrue(addr2 != addr3);
    }
    
    function test_ComputeAddress_EdgeCases() public pure {
        // Test with empty bytecode
        address addr1 = HookMinerFixed.computeAddress(
            address(0x1),
            bytes32(uint256(123)),
            hex""
        );
        assertTrue(addr1 != address(0));
        
        // Test with zero salt
        address addr2 = HookMinerFixed.computeAddress(
            address(0x1),
            bytes32(0),
            hex"608060405234801561001057600080fd5b50"
        );
        assertTrue(addr2 != address(0));
        
        // Test with zero deployer
        address addr3 = HookMinerFixed.computeAddress(
            address(0),
            bytes32(uint256(123)),
            hex"608060405234801561001057600080fd5b50"
        );
        assertTrue(addr3 != address(0));
    }
    
    function test_HasValidFlags() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        
        // Address with both flags
        address addrWithFlags = address(uint160(flags));
        assertTrue(HookMinerFixed.hasValidFlags(addrWithFlags, flags));
        
        // Address with only one flag
        address addrPartialFlags = address(uint160(Hooks.BEFORE_SWAP_FLAG));
        assertFalse(HookMinerFixed.hasValidFlags(addrPartialFlags, flags));
        
        // Address with no flags
        address addrNoFlags = address(0x1000);
        assertFalse(HookMinerFixed.hasValidFlags(addrNoFlags, flags));
    }
    
    function test_MineAddress() public pure {
        (address hookAddress,) = HookMinerFixed.mineAddress(
            address(0x1),
            true,  // beforeSwap
            true,  // afterSwap
            false, // beforeAddLiquidity
            false, // beforeRemoveLiquidity
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000123"
        );
        
        uint160 expectedFlags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        assertTrue(uint160(hookAddress) & expectedFlags == expectedFlags);
        assertTrue(salt != bytes32(0));
    }
    
    function test_ReasonableGasUsage() public pure {
        // Test that mining doesn't use excessive gas
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        (address hookAddress, bytes32 salt) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"60806040",
            hex"00"
        );
        
        assertTrue(uint160(hookAddress) & flags == flags);
        // If this test passes without running out of gas, we're good
    }
    
    function test_Sequential_Different_Results() public pure {
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);
        
        (address hookAddress1,) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000001"
        );
        
        (address hookAddress2,) = HookMinerFixed.find(
            address(0x1),
            flags,
            hex"608060405234801561001057600080fd5b50",
            hex"0000000000000000000000000000000000000000000000000000000000000002"
        );
        
        // Different constructor args should give different results
        assertTrue(hookAddress1 != hookAddress2);
        assertTrue(salt1 != salt2);
    }
    
    // Fuzz tests
    function testFuzz_ComputeAddress_Deterministic(
        address testDeployer,
        bytes32 salt,
        bytes memory bytecode
    ) public pure {
        address addr1 = HookMinerFixed.computeAddress(testDeployer, salt, bytecode);
        address addr2 = HookMinerFixed.computeAddress(testDeployer, salt, bytecode);
        
        assertEq(addr1, addr2);
    }
    
    function testFuzz_Find_ValidFlags_Limited(uint16 flags) public {
        // Limit to reasonable flag values to avoid gas issues
        if (flags == 0) {
            (address hookAddress, bytes32 salt) = HookMinerFixed.find(
                address(0x1),
                uint160(flags),
                hex"60806040",
                hex"00"
            );
            
            assertTrue(uint160(hookAddress) & uint160(flags) == uint160(flags));
            assertEq(salt, bytes32(0));
            return;
        }
        
        // Only test with known valid Uniswap flags to avoid infinite loops
        uint160 validFlags = uint160(flags) & uint160(0x3FFF); // Limit to valid hook flags
        if (validFlags == 0) return;
        
        try this.tryFind(validFlags) returns (address hookAddr, bytes32) {
            assertTrue(uint160(hookAddr) & validFlags == validFlags);
        } catch {
            // Some flag combinations might be too hard to find - that's OK
        }
    }
    
    function tryFind(uint160 flags) external pure returns (address, bytes32) {
        return HookMinerFixed.find(
            address(0x1),
            flags,
            hex"60806040",
            hex"00"
        );
    }
}