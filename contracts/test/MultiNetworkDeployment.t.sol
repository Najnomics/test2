// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {MultiNetworkDeployment} from "../script/MultiNetworkDeployment.s.sol";
import {BaseDeployment} from "../script/BaseDeployment.s.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";

contract MultiNetworkDeploymentTest is Test {
    MultiNetworkDeployment public deployment;
    
    address public deployer = address(0x1234);
    address public feeRecipient = address(0x5678);
    uint256 public deployerPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public {
        deployment = new MultiNetworkDeployment();
        
        // Set up environment variables for testing
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
    }
    
    function test_Constructor() public {
        // Constructor should complete without revert
        MultiNetworkDeployment newDeployment = new MultiNetworkDeployment();
        assertTrue(address(newDeployment) != address(0));
    }
    
    function test_NetworkSupport() public {
        // Multi-network deployment should support all configured networks
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
    
    function test_Run_SingleNetwork() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Mock environment variables
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        // Run deployment on single network
        BaseDeployment.DeploymentResult[] memory results = deployment.run();
        
        // Verify we got results
        assertTrue(results.length > 0);
        BaseDeployment.DeploymentResult memory result = results[0];
        
        // Verify deployment result
        assertTrue(result.hook != address(0));
        assertTrue(result.priceOracle != address(0));
        assertTrue(result.serviceManager != address(0));
        assertTrue(result.priceFeedConfig != address(0));
        assertEq(result.deployer, vm.addr(deployerPrivateKey));
        assertEq(result.chainId, 31337);
        assertEq(result.networkName, "Local/Anvil");
    }
    
    function test_MultiNetworkConfiguration() public {
        // Test configuration for different networks
        
        // Mainnet configuration
        vm.chainId(1);
        BaseDeployment.NetworkConfig memory mainnetConfig = deployment.getCurrentNetworkConfig();
        assertEq(mainnetConfig.networkName, "Ethereum Mainnet");
        assertEq(mainnetConfig.lvrThreshold, 50);
        assertEq(mainnetConfig.minimumStake, 32 ether);
        
        // Sepolia configuration
        vm.chainId(11155111);
        BaseDeployment.NetworkConfig memory sepoliaConfig = deployment.getCurrentNetworkConfig();
        assertEq(sepoliaConfig.networkName, "Sepolia Testnet");
        assertEq(sepoliaConfig.lvrThreshold, 100);
        assertEq(sepoliaConfig.minimumStake, 1 ether);
        
        // Base configuration
        vm.chainId(8453);
        BaseDeployment.NetworkConfig memory baseConfig = deployment.getCurrentNetworkConfig();
        assertEq(baseConfig.networkName, "Base");
        assertEq(baseConfig.lvrThreshold, 75);
        assertEq(baseConfig.minimumStake, 16 ether);
        
        // Arbitrum configuration
        vm.chainId(42161);
        BaseDeployment.NetworkConfig memory arbitrumConfig = deployment.getCurrentNetworkConfig();
        assertEq(arbitrumConfig.networkName, "Arbitrum One");
        assertEq(arbitrumConfig.lvrThreshold, 75);
        assertEq(arbitrumConfig.minimumStake, 16 ether);
    }
    
    function test_NetworkSpecificDeployment() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult[] memory results = deployment.run();
        assertTrue(results.length > 0);
        BaseDeployment.DeploymentResult memory result = results[0];
        
        // Verify network-specific configurations are applied
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        
        assertEq(hook.lvrThreshold(), config.lvrThreshold);
        assertEq(hook.feeRecipient(), feeRecipient);
        
        // Check that hook has proper permissions
        assertTrue(hook.authorizedOperators(result.deployer));
        assertTrue(hook.authorizedOperators(result.serviceManager));
    }
    
    function test_DefaultFeeRecipient() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Don't set FEE_RECIPIENT to test default behavior
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        
        BaseDeployment.DeploymentResult[] memory results = deployment.run();
        assertTrue(results.length > 0);
        BaseDeployment.DeploymentResult memory result = results[0];
        
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
        
        // Test with valid PRIVATE_KEY
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        
        // Should work now
        BaseDeployment.DeploymentResult[] memory results = deployment.run();
        assertTrue(results.length > 0);
        BaseDeployment.DeploymentResult memory result = results[0];
        assertTrue(result.hook != address(0));
    }
    
    function test_MultiNetworkConsistency() public {
        // Test that the same configuration produces consistent results across networks
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        // Deploy on local network
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        BaseDeployment.DeploymentResult[] memory localResults = deployment.run();
        assertTrue(localResults.length > 0);
        BaseDeployment.DeploymentResult memory localResult = localResults[0];
        
        // Reset for second deployment
        deployment = new MultiNetworkDeployment();
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        // Deploy on another supported network (using same local for testing)
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        BaseDeployment.DeploymentResult[] memory secondResults = deployment.run();
        assertTrue(secondResults.length > 0);
        BaseDeployment.DeploymentResult memory secondResult = secondResults[0];
        
        // Verify consistent behavior (different addresses but same configuration)
        EigenLVRHook hook1 = EigenLVRHook(payable(localResult.hook));
        EigenLVRHook hook2 = EigenLVRHook(payable(secondResult.hook));
        
        assertEq(hook1.lvrThreshold(), hook2.lvrThreshold());
        assertEq(hook1.feeRecipient(), hook2.feeRecipient());
    }
    
    function test_ContractDeploymentConsistency() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult[] memory results = deployment.run();
        assertTrue(results.length > 0);
        BaseDeployment.DeploymentResult memory result = results[0];
        
        // All contracts should be deployed and unique
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
    
    function test_NetworkNameMapping() public {
        // Test network name retrieval for all supported networks
        assertEq(deployment.getNetworkName(1), "Ethereum Mainnet");
        assertEq(deployment.getNetworkName(11155111), "Sepolia Testnet");
        assertEq(deployment.getNetworkName(8453), "Base");
        assertEq(deployment.getNetworkName(42161), "Arbitrum One");
        assertEq(deployment.getNetworkName(31337), "Local/Anvil");
        assertEq(deployment.getNetworkName(999999), "Unknown Network");
    }
    
    function testFuzz_MultiNetworkWithRandomRecipients(address _feeRecipient) public {
        vm.assume(_feeRecipient != address(0));
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(_feeRecipient));
        
        BaseDeployment.DeploymentResult[] memory results = deployment.run();
        assertTrue(results.length > 0);
        BaseDeployment.DeploymentResult memory result = results[0];
        
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertEq(hook.feeRecipient(), _feeRecipient);
    }
    
    function test_MultiNetworkGasEfficiency() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        uint256 gasBefore = gasleft();
        BaseDeployment.DeploymentResult[] memory results = deployment.run();
        assertTrue(results.length > 0);
        BaseDeployment.DeploymentResult memory result = results[0];
        uint256 gasUsed = gasBefore - gasleft();
        
        // Log gas usage for monitoring
        console.log("Multi-network deployment gas used:", gasUsed);
        
        // Verify deployment was successful
        assertTrue(result.hook != address(0));
        
        // Multi-network deployment should be efficient
        assertTrue(gasUsed < 12_000_000);
    }
    
    function test_MultiNetworkDeploymentResult() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult[] memory results = deployment.run();
        assertTrue(results.length > 0);
        BaseDeployment.DeploymentResult memory result = results[0];
        
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