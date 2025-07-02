// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {DeploymentUtils} from "../script/DeploymentUtils.s.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {EigenLVRAVSServiceManager} from "../src/EigenLVRAVSServiceManager.sol";
import {ProductionPriceFeedConfig} from "../src/ProductionPriceFeedConfig.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

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

contract DeploymentUtilsTest is Test {
    DeploymentUtils public utils;
    
    EigenLVRHook public hook;
    ChainlinkPriceOracle public priceOracle;
    EigenLVRAVSServiceManager public serviceManager;
    ProductionPriceFeedConfig public priceFeedConfig;
    
    MockPoolManager public mockPoolManager;
    MockAVSDirectory public mockAVSDirectory;
    
    address public deployer = address(0x1234);
    address public feeRecipient = address(0x5678);
    
    function setUp() public {
        utils = new DeploymentUtils();
        mockPoolManager = new MockPoolManager();
        mockAVSDirectory = new MockAVSDirectory();
        
        vm.chainId(31337);
        vm.deal(deployer, 10 ether);
        
        // Deploy test contracts
        vm.startPrank(deployer);
        
        priceOracle = new ChainlinkPriceOracle(deployer);
        serviceManager = new EigenLVRAVSServiceManager(mockAVSDirectory);
        priceFeedConfig = new ProductionPriceFeedConfig(priceOracle);
        hook = new EigenLVRHook(
            IPoolManager(address(mockPoolManager)),
            mockAVSDirectory,
            priceOracle,
            feeRecipient,
            50
        );
        
        vm.stopPrank();
    }
    
    function test_VerifyDeployment_AllValid() public {
        (bool result, string memory report) = utils.verifyDeployment(
            address(hook),
            address(priceOracle),
            address(serviceManager),
            address(priceFeedConfig)
        );
        
        assertTrue(result);
        assertEq(report, "All contracts verified successfully");
    }
    
    function test_VerifyDeployment_InvalidHook() public {
        (bool result, string memory report) = utils.verifyDeployment(
            address(0),
            address(priceOracle),
            address(serviceManager),
            address(priceFeedConfig)
        );
        
        assertFalse(result);
        assertTrue(bytes(report).length > 0);
    }
    
    function test_VerifyDeployment_InvalidPriceOracle() public {
        (bool result, string memory report) = utils.verifyDeployment(
            address(hook),
            address(0),
            address(serviceManager),
            address(priceFeedConfig)
        );
        
        assertFalse(result);
        assertTrue(bytes(report).length > 0);
    }
    
    function test_VerifyDeployment_InvalidServiceManager() public {
        (bool result, string memory report) = utils.verifyDeployment(
            address(hook),
            address(priceOracle),
            address(0),
            address(priceFeedConfig)
        );
        
        assertFalse(result);
        assertTrue(bytes(report).length > 0);
    }
    
    function test_VerifyDeployment_InvalidPriceFeedConfig() public {
        (bool result, string memory report) = utils.verifyDeployment(
            address(hook),
            address(priceOracle),
            address(serviceManager),
            address(0)
        );
        
        assertFalse(result);
        assertTrue(bytes(report).length > 0);
    }
    
    function test_VerifyHook_Valid() public {
        (bool result, string memory report) = utils.verifyHook(address(hook));
        
        assertTrue(result);
        assertEq(report, "Hook verified");
    }
    
    function test_VerifyHook_Invalid() public {
        (bool result, string memory report) = utils.verifyHook(address(0));
        
        assertFalse(result);
        assertEq(report, "Hook address is zero");
    }
    
    function test_VerifyPriceOracle_Valid() public {
        (bool result, string memory report) = utils.verifyPriceOracle(address(priceOracle));
        
        assertTrue(result);
        assertEq(report, "Price oracle verified");
    }
    
    function test_VerifyPriceOracle_Invalid() public {
        (bool result, string memory report) = utils.verifyPriceOracle(address(0));
        
        assertFalse(result);
        assertEq(report, "Oracle address is zero");
    }
    
    function test_VerifyServiceManager_Valid() public {
        (bool result, string memory report) = utils.verifyServiceManager(address(serviceManager));
        
        assertTrue(result);
        assertEq(report, "Service manager verified");
    }
    
    function test_VerifyServiceManager_Invalid() public {
        (bool result, string memory report) = utils.verifyServiceManager(address(0));
        
        assertFalse(result);
        assertEq(report, "Service manager address is zero");
    }
    
    function test_VerifyPriceFeedConfig_Valid() public {
        (bool result, string memory report) = utils.verifyPriceFeedConfig(address(priceFeedConfig));
        
        assertTrue(result);
        assertTrue(bytes(report).length > 0);
    }
    
    function test_VerifyPriceFeedConfig_Invalid() public {
        (bool result, string memory report) = utils.verifyPriceFeedConfig(address(0));
        
        assertFalse(result);
        assertEq(report, "Price feed config address is zero");
    }
    
    function test_SystemIntegration() public {
        // Test complete integration
        (bool hookOk, ) = utils.verifyHook(address(hook));
        (bool oracleOk, ) = utils.verifyPriceOracle(address(priceOracle));
        (bool smOk, ) = utils.verifyServiceManager(address(serviceManager));
        (bool pfcOk, ) = utils.verifyPriceFeedConfig(address(priceFeedConfig));
        
        assertTrue(hookOk);
        assertTrue(oracleOk);
        assertTrue(smOk);
        assertTrue(pfcOk);
        
        // Test complete verification
        (bool allOk, string memory report) = utils.verifyDeployment(
            address(hook),
            address(priceOracle),
            address(serviceManager),
            address(priceFeedConfig)
        );
        
        assertTrue(allOk);
        assertEq(report, "All contracts verified successfully");
    }
    
    function testFuzz_VerifyDeployment_RandomAddresses(
        address _hook,
        address _oracle,
        address _serviceManager,
        address _config
    ) public {
        (bool result, string memory report) = utils.verifyDeployment(_hook, _oracle, _serviceManager, _config);
        
        // Should only be true if all addresses are non-zero and valid contracts
        if (_hook == address(0) || _oracle == address(0) || 
            _serviceManager == address(0) || _config == address(0)) {
            assertFalse(result);
            assertTrue(bytes(report).length > 0);
        }
    }
    
    function test_Utils_Constructor() public {
        DeploymentUtils newUtils = new DeploymentUtils();
        // Constructor should not revert
        assertTrue(address(newUtils) != address(0));
    }
    
    function test_BatchVerification() public {
        address[] memory hooks = new address[](2);
        address[] memory oracles = new address[](2);
        address[] memory serviceManagers = new address[](2);
        address[] memory configs = new address[](2);
        
        hooks[0] = address(hook);
        oracles[0] = address(priceOracle);
        serviceManagers[0] = address(serviceManager);
        configs[0] = address(priceFeedConfig);
        
        hooks[1] = address(0);
        oracles[1] = address(0);
        serviceManagers[1] = address(0);
        configs[1] = address(0);
        
        // Test individual verification in a loop
        (bool result1, ) = utils.verifyDeployment(hooks[0], oracles[0], serviceManagers[0], configs[0]);
        (bool result2, ) = utils.verifyDeployment(hooks[1], oracles[1], serviceManagers[1], configs[1]);
        
        assertTrue(result1);
        assertFalse(result2);
    }
}