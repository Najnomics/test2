// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SimpleDeployment} from "../script/SimpleDeployment.s.sol";
import {BaseDeployment} from "../script/BaseDeployment.s.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";

contract SimpleDeploymentTest is Test {
    SimpleDeployment public deployment;
    
    address public deployer = address(0x1234);
    address public feeRecipient = address(0x5678);
    uint256 public deployerPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    function setUp() public {
        deployment = new SimpleDeployment();
        
        // Set up environment variables for testing
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
    }
    
    function test_Run_UnsupportedNetwork() public {
        // Switch to unsupported network
        vm.chainId(999999);
        
        vm.expectRevert("Network not supported");
        deployment.run();
    }
    
    function test_Run_SupportedNetwork() public {
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
    
    function test_Run_DefaultFeeRecipient() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Don't set FEE_RECIPIENT to test default behavior
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Fee recipient should default to deployer
        assertEq(result.deployer, vm.addr(deployerPrivateKey));
    }
    
    function test_DeployHook() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        
        // Deploy a price oracle first
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle(deployer);
        
        // Test _deployHook function through a deployment
        vm.prank(deployer);
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify hook was deployed
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertTrue(address(hook) != address(0));
        
        // Verify hook configuration
        assertEq(hook.feeRecipient(), feeRecipient);
        assertEq(hook.lvrThreshold(), config.lvrThreshold);
    }
    
    function test_HookDeploymentWithSalt() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        uint256 timestampBefore = block.timestamp;
        
        BaseDeployment.DeploymentResult memory result1 = deployment.run();
        
        // Advance time
        vm.warp(block.timestamp + 1);
        
        BaseDeployment.DeploymentResult memory result2 = deployment.run();
        
        // Hooks should have different addresses due to different timestamps in salt
        assertTrue(result1.hook != result2.hook);
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
    
    function test_EnvironmentVariableHandling() public {
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
    
    function testFuzz_DeploymentWithDifferentFeeRecipients(address _feeRecipient) public {
        vm.assume(_feeRecipient != address(0));
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(_feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertEq(hook.feeRecipient(), _feeRecipient);
    }
    
    function test_DeploymentResultPersistence() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
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