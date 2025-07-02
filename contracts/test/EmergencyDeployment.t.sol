// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EmergencyDeployment} from "../script/EmergencyDeployment.s.sol";
import {BaseDeployment} from "../script/BaseDeployment.s.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";

contract EmergencyDeploymentTest is Test {
    EmergencyDeployment public deployment;
    
    address public deployer = address(0x1234);
    address public emergencyFeeRecipient = address(0x5678);
    uint256 public emergencyPrivateKey = 0x2222222222222222222222222222222222222222222222222222222222222222;
    
    function setUp() public {
        deployment = new EmergencyDeployment();
        
        // Set up emergency environment variables
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(emergencyFeeRecipient));
    }
    
    function test_Constructor() public {
        // Constructor should complete without revert
        EmergencyDeployment newDeployment = new EmergencyDeployment();
        assertTrue(address(newDeployment) != address(0));
    }
    
    function test_NetworkSupport() public {
        // Emergency deployment should support all networks
        uint256[] memory supportedChainIds = new uint256[](5);
        supportedChainIds[0] = 1;        // Mainnet
        supportedChainIds[1] = 11155111; // Sepolia
        supportedChainIds[2] = 8453;     // Base
        supportedChainIds[3] = 42161;    // Arbitrum
        supportedChainIds[4] = 31337;    // Local
        
        for (uint256 i = 0; i < supportedChainIds.length; i++) {
            vm.chainId(supportedChainIds[i]);
            assertTrue(deployment.isNetworkSupported());
        }
    }
    
    function test_Run_UnsupportedNetwork() public {
        // Switch to unsupported network
        vm.chainId(999999);
        
        vm.expectRevert("Network not supported");
        deployment.run();
    }
    
    function test_Run_EmergencyDeployment() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        // Mock emergency environment variables
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(emergencyFeeRecipient));
        
        // Run emergency deployment
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify deployment result
        assertTrue(result.hook != address(0));
        assertTrue(result.priceOracle != address(0));
        assertTrue(result.serviceManager != address(0));
        assertTrue(result.priceFeedConfig != address(0));
        assertEq(result.deployer, vm.addr(emergencyPrivateKey));
        assertEq(result.chainId, 31337);
        assertEq(result.networkName, "Local/Anvil");
    }
    
    function test_EmergencyConfiguration() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(emergencyFeeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify emergency-specific configurations
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        
        // Emergency deployment should start paused for safety
        assertTrue(hook.paused());
        
        // Check proper fee recipient
        assertEq(hook.feeRecipient(), emergencyFeeRecipient);
        
        // Check that emergency deployer has authorization
        assertTrue(hook.authorizedOperators(result.deployer));
    }
    
    function test_EmergencyFallbackFeeRecipient() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        // Don't set EMERGENCY_FEE_RECIPIENT to test fallback
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Fee recipient should fallback to emergency deployer
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertEq(hook.feeRecipient(), vm.addr(emergencyPrivateKey));
    }
    
    function test_EmergencyEnvironmentValidation() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        // Test with missing EMERGENCY_PRIVATE_KEY
        vm.setEnv("EMERGENCY_PRIVATE_KEY", "");
        vm.expectRevert();
        deployment.run();
        
        // Test with valid EMERGENCY_PRIVATE_KEY
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        
        // Should work now
        BaseDeployment.DeploymentResult memory result = deployment.run();
        assertTrue(result.hook != address(0));
    }
    
    function test_EmergencyDeploymentSafety() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(emergencyFeeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        
        // Emergency deployment should be paused by default
        assertTrue(hook.paused());
        
        // Only emergency deployer should be authorized initially
        assertTrue(hook.authorizedOperators(result.deployer));
        
        // Hook should have emergency-appropriate settings
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        assertEq(hook.lvrThreshold(), config.lvrThreshold);
    }
    
    function test_EmergencyContractValidation() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(emergencyFeeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // All emergency contracts should be deployed correctly
        assertTrue(result.priceOracle.code.length > 0);
        assertTrue(result.serviceManager.code.length > 0);
        assertTrue(result.priceFeedConfig.code.length > 0);
        assertTrue(result.hook.code.length > 0);
        
        // Verify they're all different addresses
        assertTrue(result.priceOracle != result.serviceManager);
        assertTrue(result.priceOracle != result.priceFeedConfig);
        assertTrue(result.priceOracle != result.hook);
        assertTrue(result.serviceManager != result.priceFeedConfig);
        assertTrue(result.serviceManager != result.hook);
        assertTrue(result.priceFeedConfig != result.hook);
    }
    
    function test_MultipleEmergencyDeployments() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(emergencyFeeRecipient));
        
        // First emergency deployment
        BaseDeployment.DeploymentResult memory result1 = deployment.run();
        
        // Second emergency deployment should also work
        BaseDeployment.DeploymentResult memory result2 = deployment.run();
        
        // Results should be different (different addresses)
        assertTrue(result1.hook != result2.hook);
        assertTrue(result1.priceOracle != result2.priceOracle);
        assertTrue(result1.serviceManager != result2.serviceManager);
        assertTrue(result1.priceFeedConfig != result2.priceFeedConfig);
        
        // Both should be paused initially
        EigenLVRHook hook1 = EigenLVRHook(payable(result1.hook));
        EigenLVRHook hook2 = EigenLVRHook(payable(result2.hook));
        assertTrue(hook1.paused());
        assertTrue(hook2.paused());
    }
    
    function testFuzz_EmergencyWithRandomRecipients(address _emergencyRecipient) public {
        vm.assume(_emergencyRecipient != address(0));
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(_emergencyRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertEq(hook.feeRecipient(), _emergencyRecipient);
        
        // Should still be paused for safety
        assertTrue(hook.paused());
    }
    
    function test_EmergencyGasUsage() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(emergencyFeeRecipient));
        
        uint256 gasBefore = gasleft();
        BaseDeployment.DeploymentResult memory result = deployment.run();
        uint256 gasUsed = gasBefore - gasleft();
        
        // Log gas usage for monitoring
        console.log("Emergency deployment gas used:", gasUsed);
        
        // Verify deployment was successful
        assertTrue(result.hook != address(0));
        
        // Emergency deployment should be efficient
        assertTrue(gasUsed < 12_000_000);
    }
    
    function test_EmergencyDeploymentResult() public {
        vm.chainId(31337);
        vm.deal(vm.addr(emergencyPrivateKey), 10 ether);
        
        vm.setEnv("EMERGENCY_PRIVATE_KEY", vm.toString(emergencyPrivateKey));
        vm.setEnv("EMERGENCY_FEE_RECIPIENT", vm.toString(emergencyFeeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Check that deployment result is stored
        BaseDeployment.DeploymentResult memory storedResult = deployment.deploymentResult();
        
        assertEq(storedResult.hook, result.hook);
        assertEq(storedResult.priceOracle, result.priceOracle);
        assertEq(storedResult.serviceManager, result.serviceManager);
        assertEq(storedResult.priceFeedConfig, result.priceFeedConfig);
        assertEq(storedResult.deployer, result.deployer);
        assertEq(storedResult.chainId, result.chainId);
        assertEq(storedResult.networkName, result.networkName);
        assertEq(storedResult.deploymentTime, result.deploymentTime);
    }
}