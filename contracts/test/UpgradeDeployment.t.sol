// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {UpgradeDeployment} from "../script/UpgradeDeployment.s.sol";
import {BaseDeployment} from "../script/BaseDeployment.s.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";

contract UpgradeDeploymentTest is Test {
    UpgradeDeployment public deployment;
    
    address public deployer = address(0x1234);
    address public feeRecipient = address(0x5678);
    uint256 public deployerPrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    
    // Mock old contract addresses
    address public oldHook = address(0x1111);
    address public oldPriceOracle = address(0x2222);
    address public oldServiceManager = address(0x3333);
    address public oldPriceFeedConfig = address(0x4444);
    
    function setUp() public {
        deployment = new UpgradeDeployment();
        
        // Set up environment variables for testing
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        // Set up old contract addresses for upgrade scenario
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        vm.setEnv("OLD_PRICE_ORACLE_ADDRESS", vm.toString(oldPriceOracle));
        vm.setEnv("OLD_SERVICE_MANAGER_ADDRESS", vm.toString(oldServiceManager));
        vm.setEnv("OLD_PRICE_FEED_CONFIG_ADDRESS", vm.toString(oldPriceFeedConfig));
    }
    
    function test_Constructor() public {
        // Constructor should complete without revert
        UpgradeDeployment newDeployment = new UpgradeDeployment();
        assertTrue(address(newDeployment) != address(0));
    }
    
    function test_NetworkSupport() public {
        // Upgrade deployment should support all networks
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
    
    function test_Run_UpgradeDeployment() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Mock environment variables
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        vm.setEnv("OLD_PRICE_ORACLE_ADDRESS", vm.toString(oldPriceOracle));
        
        // Run upgrade deployment
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify deployment result
        assertTrue(result.hook != address(0));
        assertTrue(result.priceOracle != address(0));
        assertTrue(result.serviceManager != address(0));
        assertTrue(result.priceFeedConfig != address(0));
        assertEq(result.deployer, vm.addr(deployerPrivateKey));
        assertEq(result.chainId, 31337);
        assertEq(result.networkName, "Local/Anvil");
        
        // New addresses should be different from old ones
        assertTrue(result.hook != oldHook);
        assertTrue(result.priceOracle != oldPriceOracle);
        assertTrue(result.serviceManager != oldServiceManager);
        assertTrue(result.priceFeedConfig != oldPriceFeedConfig);
    }
    
    function test_UpgradeConfiguration() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Verify upgrade-specific configurations
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        
        // Check that hook has proper permissions
        assertTrue(hook.authorizedOperators(result.deployer));
        assertTrue(hook.authorizedOperators(result.serviceManager));
        
        // Verify hook configuration
        assertEq(hook.feeRecipient(), feeRecipient);
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        assertEq(hook.lvrThreshold(), config.lvrThreshold);
        
        // Upgraded hook should not be paused (ready for migration)
        assertFalse(hook.paused());
    }
    
    function test_UpgradeWithoutOldAddresses() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Don't set old addresses - should still work as fresh deployment
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // Should still deploy successfully
        assertTrue(result.hook != address(0));
        assertTrue(result.priceOracle != address(0));
        assertTrue(result.serviceManager != address(0));
        assertTrue(result.priceFeedConfig != address(0));
    }
    
    function test_DefaultFeeRecipient() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Don't set FEE_RECIPIENT to test default behavior
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        
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
    
    function test_UpgradeContractValidation() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        // All upgrade contracts should be deployed correctly
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
    
    function test_MultipleUpgradeDeployments() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        
        // First upgrade deployment
        BaseDeployment.DeploymentResult memory result1 = deployment.run();
        
        // Second upgrade deployment should also work
        BaseDeployment.DeploymentResult memory result2 = deployment.run();
        
        // Results should be different (different addresses)
        assertTrue(result1.hook != result2.hook);
        assertTrue(result1.priceOracle != result2.priceOracle);
        assertTrue(result1.serviceManager != result2.serviceManager);
        assertTrue(result1.priceFeedConfig != result2.priceFeedConfig);
        
        // Both should have same configuration
        EigenLVRHook hook1 = EigenLVRHook(payable(result1.hook));
        EigenLVRHook hook2 = EigenLVRHook(payable(result2.hook));
        assertEq(hook1.lvrThreshold(), hook2.lvrThreshold());
        assertEq(hook1.feeRecipient(), hook2.feeRecipient());
    }
    
    function test_UpgradePreservesConfiguration() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        
        // Configuration should match network settings
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        assertEq(hook.lvrThreshold(), config.lvrThreshold);
        assertEq(hook.feeRecipient(), feeRecipient);
        
        // Deployer should have authorization
        assertTrue(hook.authorizedOperators(result.deployer));
    }
    
    function testFuzz_UpgradeWithRandomRecipients(address _feeRecipient) public {
        vm.assume(_feeRecipient != address(0));
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(_feeRecipient));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        
        BaseDeployment.DeploymentResult memory result = deployment.run();
        
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        assertEq(hook.feeRecipient(), _feeRecipient);
    }
    
    function test_UpgradeGasUsage() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        
        uint256 gasBefore = gasleft();
        BaseDeployment.DeploymentResult memory result = deployment.run();
        uint256 gasUsed = gasBefore - gasleft();
        
        // Log gas usage for monitoring
        console.log("Upgrade deployment gas used:", gasUsed);
        
        // Verify deployment was successful
        assertTrue(result.hook != address(0));
        
        // Upgrade deployment should be efficient
        assertTrue(gasUsed < 12_000_000);
    }
    
    function test_UpgradeDeploymentResult() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerPrivateKey));
        vm.setEnv("FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("OLD_HOOK_ADDRESS", vm.toString(oldHook));
        
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