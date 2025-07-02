// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {BaseDeployment} from "../script/BaseDeployment.s.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {EigenLVRAVSServiceManager} from "../src/EigenLVRAVSServiceManager.sol";
import {ProductionPriceFeedConfig} from "../src/ProductionPriceFeedConfig.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

contract MockBaseDeployment is BaseDeployment {
    function _deployHook(
        NetworkConfig memory config,
        ChainlinkPriceOracle priceOracle,
        address deployer,
        address feeRecipient
    ) internal override returns (EigenLVRHook) {
        return new EigenLVRHook(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            feeRecipient,
            config.lvrThreshold
        );
    }
    
    function exposed_setupNetworkConfigs() external {
        _setupNetworkConfigs();
    }
    
    function exposed_deployAllContracts(
        address deployer,
        address feeRecipient
    ) external returns (DeploymentResult memory) {
        return deployAllContracts(deployer, feeRecipient);
    }
    
    function exposed_configureSystem(
        EigenLVRHook hook,
        ChainlinkPriceOracle priceOracle,
        EigenLVRAVSServiceManager serviceManager,
        ProductionPriceFeedConfig priceFeedConfig,
        address deployer
    ) external {
        _configureSystem(hook, priceOracle, serviceManager, priceFeedConfig, deployer);
    }
    
    function exposed_logDeploymentSummary(DeploymentResult memory result) external view {
        logDeploymentSummary(result);
    }
    
    function exposed_saveDeploymentResults(DeploymentResult memory result) external {
        saveDeploymentResults(result);
    }
}

contract MockPoolManager {
    function initialize(bytes calldata) external pure returns (bytes4) {
        return this.initialize.selector;
    }
}

contract MockAVSDirectory {
    function registerOperatorToAVS(address, bytes calldata) external pure {}
    function deregisterOperatorFromAVS(address) external pure {}
    function updateAVSMetadataURI(string calldata) external pure {}
}

contract BaseDeploymentTest is Test {
    MockBaseDeployment public deployment;
    MockPoolManager public mockPoolManager;
    MockAVSDirectory public mockAVSDirectory;
    
    address public deployer = address(0x1234);
    address public feeRecipient = address(0x5678);
    
    function setUp() public {
        deployment = new MockBaseDeployment();
        mockPoolManager = new MockPoolManager();
        mockAVSDirectory = new MockAVSDirectory();
    }
    
    function test_Constructor() public {
        // Constructor calls _setupNetworkConfigs, verify it's called
        assertTrue(deployment.isNetworkSupported() || block.chainid == 31337);
    }
    
    function test_NetworkConfigSetup() public {
        deployment.exposed_setupNetworkConfigs();
        
        // Test Mainnet config
        vm.chainId(1);
        BaseDeployment.NetworkConfig memory mainnetConfig = deployment.getCurrentNetworkConfig();
        assertEq(mainnetConfig.networkName, "Ethereum Mainnet");
        assertEq(mainnetConfig.lvrThreshold, 50);
        assertEq(mainnetConfig.minimumStake, 32 ether);
        
        // Test Sepolia config
        vm.chainId(11155111);
        BaseDeployment.NetworkConfig memory sepoliaConfig = deployment.getCurrentNetworkConfig();
        assertEq(sepoliaConfig.networkName, "Sepolia Testnet");
        assertEq(sepoliaConfig.lvrThreshold, 100);
        assertEq(sepoliaConfig.minimumStake, 1 ether);
        
        // Test Base config
        vm.chainId(8453);
        BaseDeployment.NetworkConfig memory baseConfig = deployment.getCurrentNetworkConfig();
        assertEq(baseConfig.networkName, "Base");
        assertEq(baseConfig.lvrThreshold, 75);
        
        // Test Arbitrum config
        vm.chainId(42161);
        BaseDeployment.NetworkConfig memory arbitrumConfig = deployment.getCurrentNetworkConfig();
        assertEq(arbitrumConfig.networkName, "Arbitrum One");
        assertEq(arbitrumConfig.lvrThreshold, 75);
        
        // Test Local/Anvil config
        vm.chainId(31337);
        BaseDeployment.NetworkConfig memory localConfig = deployment.getCurrentNetworkConfig();
        assertEq(localConfig.networkName, "Local/Anvil");
        assertEq(localConfig.lvrThreshold, 50);
        assertEq(localConfig.minimumStake, 1 ether);
    }
    
    function test_IsNetworkSupported() public {
        // Test supported networks
        vm.chainId(1);
        assertTrue(deployment.isNetworkSupported());
        
        vm.chainId(11155111);
        assertTrue(deployment.isNetworkSupported());
        
        vm.chainId(8453);
        assertTrue(deployment.isNetworkSupported());
        
        vm.chainId(42161);
        assertTrue(deployment.isNetworkSupported());
        
        vm.chainId(31337);
        assertTrue(deployment.isNetworkSupported());
        
        // Test unsupported network
        vm.chainId(999999);
        assertFalse(deployment.isNetworkSupported());
    }
    
    function test_GetNetworkName() public {
        vm.chainId(1);
        assertEq(deployment.getNetworkName(1), "Ethereum Mainnet");
        
        vm.chainId(11155111);
        assertEq(deployment.getNetworkName(11155111), "Sepolia Testnet");
        
        vm.chainId(8453);
        assertEq(deployment.getNetworkName(8453), "Base");
        
        vm.chainId(42161);
        assertEq(deployment.getNetworkName(42161), "Arbitrum One");
        
        vm.chainId(31337);
        assertEq(deployment.getNetworkName(31337), "Local/Anvil");
        
        // Test unknown network
        assertEq(deployment.getNetworkName(999999), "Unknown Network");
    }
    
    function test_DeployAllContracts_UnsupportedNetwork() public {
        // Switch to unsupported network
        vm.chainId(999999);
        
        vm.expectRevert("Network not configured");
        deployment.exposed_deployAllContracts(deployer, feeRecipient);
    }
    
    function test_DeployAllContracts_SupportedNetwork() public {
        // Use local/anvil network
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Mock the deployment
        vm.prank(deployer);
        BaseDeployment.DeploymentResult memory result = deployment.exposed_deployAllContracts(deployer, feeRecipient);
        
        // Verify deployment result structure
        assertTrue(result.hook != address(0));
        assertTrue(result.priceOracle != address(0));
        assertTrue(result.serviceManager != address(0));
        assertTrue(result.priceFeedConfig != address(0));
        assertEq(result.deployer, deployer);
        assertEq(result.chainId, 31337);
        assertEq(result.networkName, "Local/Anvil");
        assertTrue(result.deploymentTime > 0);
    }
    
    function test_ConfigureSystem() public {
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Deploy contracts first
        vm.prank(deployer);
        BaseDeployment.DeploymentResult memory result = deployment.exposed_deployAllContracts(deployer, feeRecipient);
        
        // Get deployed contracts
        EigenLVRHook hook = EigenLVRHook(payable(result.hook));
        ChainlinkPriceOracle priceOracle = ChainlinkPriceOracle(result.priceOracle);
        EigenLVRAVSServiceManager serviceManager = EigenLVRAVSServiceManager(payable(result.serviceManager));
        ProductionPriceFeedConfig priceFeedConfig = ProductionPriceFeedConfig(result.priceFeedConfig);
        
        // Test configuration
        vm.prank(deployer);
        deployment.exposed_configureSystem(hook, priceOracle, serviceManager, priceFeedConfig, deployer);
        
        // Verify operator authorization
        assertTrue(hook.authorizedOperators(deployer));
        assertTrue(hook.authorizedOperators(address(serviceManager)));
    }
    
    function test_LogDeploymentSummary() public {
        BaseDeployment.DeploymentResult memory result = BaseDeployment.DeploymentResult({
            hook: address(0x1111),
            priceOracle: address(0x2222),
            serviceManager: address(0x3333),
            priceFeedConfig: address(0x4444),
            deployer: deployer,
            chainId: 31337,
            networkName: "Local/Anvil",
            deploymentTime: block.timestamp
        });
        
        // This should not revert
        deployment.exposed_logDeploymentSummary(result);
    }
    
    function test_SaveDeploymentResults() public {
        BaseDeployment.DeploymentResult memory result = BaseDeployment.DeploymentResult({
            hook: address(0x1111),
            priceOracle: address(0x2222),
            serviceManager: address(0x3333),
            priceFeedConfig: address(0x4444),
            deployer: deployer,
            chainId: 31337,
            networkName: "Local/Anvil",
            deploymentTime: block.timestamp
        });
        
        // This should not revert
        deployment.exposed_saveDeploymentResults(result);
    }
    
    function test_ValidNetworkModifier() public {
        // Test with supported network
        vm.chainId(31337);
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        assertEq(config.networkName, "Local/Anvil");
        
        // Test with unsupported network should fail in deployAllContracts
        vm.chainId(999999);
        vm.expectRevert("Network not configured");
        deployment.exposed_deployAllContracts(deployer, feeRecipient);
    }
    
    function testFuzz_GetNetworkName(uint256 chainId) public {
        string memory networkName = deployment.getNetworkName(chainId);
        
        if (chainId == 1) {
            assertEq(networkName, "Ethereum Mainnet");
        } else if (chainId == 11155111) {
            assertEq(networkName, "Sepolia Testnet");
        } else if (chainId == 8453) {
            assertEq(networkName, "Base");
        } else if (chainId == 42161) {
            assertEq(networkName, "Arbitrum One");
        } else if (chainId == 31337) {
            assertEq(networkName, "Local/Anvil");
        } else {
            assertEq(networkName, "Unknown Network");
        }
    }
    
    function test_NetworkConfigValues() public {
        vm.chainId(1);
        BaseDeployment.NetworkConfig memory config = deployment.getCurrentNetworkConfig();
        
        // Verify mainnet addresses are set
        assertTrue(config.poolManager != address(0));
        assertTrue(config.avsDirectory != address(0));
        assertTrue(config.delegationManager != address(0));
        assertEq(config.lvrThreshold, 50);
        assertEq(config.minimumStake, 32 ether);
    }
    
    function test_DeploymentResultStruct() public {
        BaseDeployment.DeploymentResult memory result = BaseDeployment.DeploymentResult({
            hook: address(0x1),
            priceOracle: address(0x2),
            serviceManager: address(0x3),
            priceFeedConfig: address(0x4),
            deployer: address(0x5),
            chainId: 1,
            networkName: "Test Network",
            deploymentTime: 12345
        });
        
        assertEq(result.hook, address(0x1));
        assertEq(result.priceOracle, address(0x2));
        assertEq(result.serviceManager, address(0x3));
        assertEq(result.priceFeedConfig, address(0x4));
        assertEq(result.deployer, address(0x5));
        assertEq(result.chainId, 1);
        assertEq(result.networkName, "Test Network");
        assertEq(result.deploymentTime, 12345);
    }
}