// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {TestnetDeployment} from "../script/TestnetDeployment.s.sol";
import {BaseDeployment} from "../script/BaseDeployment.s.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";

contract TestnetDeploymentTest is Test {
    TestnetDeployment public deployment;
    
    address public deployer = address(0x1234);
    address public feeRecipient = address(0x5678);
    uint256 public deployerPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public {
        deployment = new TestnetDeployment();
        
        // Set up environment variables for testing
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
    }
    
    function test_Constructor() public {
        // Constructor should complete without revert
        TestnetDeployment newDeployment = new TestnetDeployment();
        assertTrue(address(newDeployment) != address(0));
    }
    
    function test_NetworkSupport() public {
        // Testnet deployment should support testnet networks
        vm.chainId(11155111); // Sepolia
        assertTrue(deployment.isNetworkSupported());
        
        vm.chainId(31337); // Local
        assertTrue(deployment.isNetworkSupported());
        
        // Should also support mainnet networks for testing
        vm.chainId(1); // Mainnet
        assertTrue(deployment.isNetworkSupported());
    }
    
    function test_Run_UnsupportedNetwork() public {
        // Switch to unsupported network
        vm.chainId(999999);
        
        vm.expectRevert("Network not supported");
        deployment.run();
    }
    
    function test_Run_SepoliaNetwork() public {
        // Use Sepolia testnet
        vm.chainId(11155111);
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
        assertEq(result.chainId, 11155111);
        assertEq(result.networkName, "Sepolia Testnet");
    }
    
    function test_Run_LocalNetwork() public {
        // Use local/anvil network
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
    
    function test_TestnetConfiguration() public {
        vm.chainId(11155111); // Sepolia
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify testnet-specific configurations
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        
        // Check that hook has proper permissions
        assertTrue(hook.authorizedOperators(result.deployer));
        assertTrue(hook.authorizedOperators(result.serviceManager));
        
        // Verify hook configuration for testnet
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        assertEq(hook.lvrThreshold(), config.lvrThreshold);
        assertEq(hook.feeRecipient(), feeRecipient);
        
        // Testnet should have higher threshold (100 vs 50 for mainnet)
        assertEq(hook.lvrThreshold(), 100);
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
        
        // Test with valid PRIVATE_KEY
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        
        // Should work now
        BaseDeployment.DeploymentResult memory result = deployment.run();
        assertTrue(result.hook != address(0));
    }
    
    function test_TestnetSpecificFeatures() public {
        vm.chainId(11155111); // Sepolia
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify testnet has lower minimum stake requirement
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        assertEq(config.minimumStake, 1 ether); // Lower than mainnet's 32 ether
        
        // Verify higher LVR threshold for testnet
        assertEq(config.lvrThreshold, 100); // Higher than mainnet's 50
    }
    
    function test_ContractDeploymentOrder() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // All contracts should be deployed
        assertTrue(result.priceOracle != address(0));
        assertTrue(result.serviceManager != address(0));
        assertTrue(result.priceFeedConfig != address(0));
        assertTrue(result.hook != address(0));
        
        // Verify they're different addresses
        assertTrue(result.priceOracle != result.serviceManager);
        assertTrue(result.priceOracle != result.priceFeedConfig);
        assertTrue(result.priceOracle != result.hook);
        assertTrue(result.serviceManager != result.priceFeedConfig);
        assertTrue(result.serviceManager != result.hook);
        assertTrue(result.priceFeedConfig != result.hook);
    }
    
    function test_MultipleTestnetDeployments() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        // First deployment
        BaseDeployment.DeploymentResult memory result1 = deployment.run();
        
        // Second deployment should work
        BaseDeployment.DeploymentResult memory result2 = deployment.run();
        
        // Results should be different (different addresses)
        assertTrue(result1.hook != result2.hook);
        assertTrue(result1.priceOracle != result2.priceOracle);
        assertTrue(result1.serviceManager != result2.serviceManager);
        assertTrue(result1.priceFeedConfig != result2.priceFeedConfig);
    }
    
    function testFuzz_DeploymentWithRandomRecipients(address _feeRecipient) public {
        vm.assume(_feeRecipient != address(0));
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(_feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertEq(hook.feeRecipient(), _feeRecipient);
    }
    
    function test_TestnetDeploymentSpeed() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        uint256 gasBefore = gasleft();
        uint256 timeBefore = block.timestamp;
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        uint256 gasUsed = gasBefore - gasleft();
        uint256 timeElapsed = block.timestamp - timeBefore;
        
        // Log metrics
        console.log("Testnet deployment gas used:", gasUsed);
        console.log("Testnet deployment time:", timeElapsed);
        
        // Verify deployment was successful
        assertTrue(result.hook != address(0));
        
        // Testnet deployment should be efficient
        assertTrue(gasUsed < 15_000_000); // Allow more gas for testnet features
    }
    
    function test_DeploymentResultConsistency() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Check that deployment result is stored and consistent
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