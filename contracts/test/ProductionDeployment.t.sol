// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ProductionDeployment} from "../script/ProductionDeployment.s.sol";
import {BaseDeployment} from "../script/BaseDeployment.s.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";

contract ProductionDeploymentTest is Test {
    ProductionDeployment public deployment;
    
    address public deployer = address(0x1234);
    address public feeRecipient = address(0x5678);
    uint256 public deployerPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public {
        deployment = new ProductionDeployment();
        
        // Set up environment variables for testing
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
    }
    
    function test_Constructor() public {
        // Constructor should complete without revert
        ProductionDeployment newDeployment = new ProductionDeployment();
        assertTrue(address(newDeployment) != address(0));
    }
    
    function test_NetworkSupport() public {
        // Test all supported networks
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
    
    function test_Run_SupportedNetwork() public {
        // Use local/anvil network for faster testing
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Mock environment variables
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        // Run deployment
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify deployment result
        assertTrue(result.hook != address(0));
        assertTrue(result.priceOracle != address(0));
        assertTrue(result.serviceManager != address(0));
        assertTrue(result.priceFeedConfig != address(0));
        assertEq(result.deployer, vm.addr(deployerPrivateKey));
        assertEq(result.chainId, 31337);
        assertEq(result.networkName, "Local/Anvil");
    }
    
    function test_HookMiningIntegration() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify hook was deployed with proper address
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertTrue(address(hook) != address(0));
        
        // Hook should be configured correctly
        assertEq(hook.feeRecipient(), feeRecipient);
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        assertEq(hook.lvrThreshold(), config.lvrThreshold);
    }
    
    function test_ProductionConfiguration() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify production-specific configurations
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        
        // Check that hook has proper permissions
        assertTrue(hook.authorizedOperators(result.deployer));
        assertTrue(hook.authorizedOperators(result.serviceManager));
        
        // Verify hook is not paused (production should be active)
        assertFalse(hook.paused());
    }
    
    function test_DefaultFeeRecipient() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Don't set FEE_RECIPIENT to test default behavior
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Fee recipient should default to deployer
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertEq(hook.feeRecipient(), vm.addr(deployerPrivateKey));
    }
    
    function test_EnvironmentVariableValidation() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Test with missing PRIVATE_KEY
        vm.setEnv("PRIVATE_KEY", "");
        vm.expectRevert();
        deployment.run();
        
        // Test with invalid PRIVATE_KEY
        vm.setEnv("PRIVATE_KEY", "invalid");
        vm.expectRevert();
        deployment.run();
        
        // Test with valid PRIVATE_KEY
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        
        // Should work now
        BaseDeployment.DeploymentResult memory result = deployment.run();
        assertTrue(result.hook != address(0));
    }
    
    function test_ContractSizeLimits() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Check that all contracts have reasonable sizes (not empty)
        assertTrue(result.hook.code.length > 0);
        assertTrue(result.priceOracle.code.length > 0);
        assertTrue(result.serviceManager.code.length > 0);
        assertTrue(result.priceFeedConfig.code.length > 0);
        
        // Log sizes for monitoring
        console.log("Hook size:", result.hook.code.length);
        console.log("Oracle size:", result.priceOracle.code.length);
        console.log("Service Manager size:", result.serviceManager.code.length);
        console.log("Config size:", result.priceFeedConfig.code.length);
    }
    
    function test_MultipleDeployments() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        // First deployment
        BaseDeployment.DeploymentResult memory result1 = deployment.run();
        
        // Second deployment should work (different salts)
        BaseDeployment.DeploymentResult memory result2 = deployment.run();
        
        // Results should be different (different addresses due to different salts)
        assertTrue(result1.hook != result2.hook);
        assertTrue(result1.priceOracle != result2.priceOracle);
        assertTrue(result1.serviceManager != result2.serviceManager);
        assertTrue(result1.priceFeedConfig != result2.priceFeedConfig);
    }
    
    function testFuzz_DeploymentWithRandomFeeRecipients(address _feeRecipient) public {
        vm.assume(_feeRecipient != address(0));
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(_feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertEq(hook.feeRecipient(), _feeRecipient);
    }
    
    function test_GasUsage() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        uint256 gasBefore = gasleft();
        BaseDeployment.DeploymentResult memory result = deployment.run();
        uint256 gasUsed = gasBefore - gasleft();
        
        // Log gas usage for monitoring
        console.log("Total deployment gas used:", gasUsed);
        
        // Verify deployment was successful
        assertTrue(result.hook != address(0));
        
        // Gas usage should be reasonable (less than 10M gas)
        assertTrue(gasUsed < 10_000_000);
    }
    
    function test_DeploymentResultPersistence() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Check that deployment result is stored
        (
            address storedHook,
            address storedPriceOracle,
            address storedServiceManager,
            address storedPriceFeedConfig,
            address storedDeployer,
            uint256 storedChainId,
            string memory storedNetworkName,
            uint256 storedDeploymentTime
        ) = deployment.deploymentResult();
        
        assertEq(storedHook, result.hook);
        assertEq(storedPriceOracle, result.priceOracle);
        assertEq(storedServiceManager, result.serviceManager);
        assertEq(storedPriceFeedConfig, result.priceFeedConfig);
        assertEq(storedDeployer, result.deployer);
        assertEq(storedChainId, result.chainId);
        assertEq(storedNetworkName, result.networkName);
        assertEq(storedDeploymentTime, result.deploymentTime);
    }
}