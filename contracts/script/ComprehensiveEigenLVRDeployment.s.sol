// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {EigenLVRAVSServiceManager} from "../src/EigenLVRAVSServiceManager.sol";
import {ProductionPriceFeedConfig} from "../src/ProductionPriceFeedConfig.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

/**
 * @title ComprehensiveEigenLVRDeployment
 * @notice Complete production deployment script for EigenLVR with all components
 */
contract ComprehensiveEigenLVRDeployment is Script {
    // CREATE2 Deployer Proxy address (same on all networks)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Network configurations
    struct DeploymentConfig {
        address poolManager;
        address avsDirectory;
        address delegationManager;
        uint256 lvrThreshold;
        uint256 minimumStake;
    }
    
    // Deployment results
    struct DeploymentResult {
        address hook;
        address priceOracle;
        address serviceManager;
        address priceFeedConfig;
        bytes32 salt;
        uint160 hookFlags;
    }
    
    function run() external returns (DeploymentResult memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== EigenLVR Complete Production Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Network:", getNetworkName());
        console.log("Chain ID:", block.chainid);
        
        // Get deployment configuration
        DeploymentConfig memory config = getDeploymentConfig();
        
        // Validate configuration
        require(config.poolManager != address(0), "Pool manager not configured");
        require(config.avsDirectory != address(0), "AVS directory not configured");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy core contracts
        DeploymentResult memory result = deployAllContracts(config, deployer);
        
        // Configure the system
        configureSystem(result, config, deployer);
        
        vm.stopBroadcast();
        
        // Log and save deployment
        logDeploymentResults(result, config);
        saveDeploymentResults(result, config);
        
        return result;
    }
    
    function deployAllContracts(
        DeploymentConfig memory config,
        address deployer
    ) internal returns (DeploymentResult memory result) {
        
        console.log("\n=== Phase 1: Core Contract Deployment ===");
        
        // 1. Deploy ChainlinkPriceOracle
        console.log("Deploying ChainlinkPriceOracle...");
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle();
        result.priceOracle = address(priceOracle);
        console.log("ChainlinkPriceOracle deployed at:", result.priceOracle);
        
        // 2. Deploy EigenLVRAVSServiceManager
        console.log("Deploying EigenLVRAVSServiceManager...");
        EigenLVRAVSServiceManager serviceManager = new EigenLVRAVSServiceManager(
            IAVSDirectory(config.avsDirectory)
        );
        result.serviceManager = address(serviceManager);
        console.log("EigenLVRAVSServiceManager deployed at:", result.serviceManager);
        
        // 3. Deploy ProductionPriceFeedConfig
        console.log("Deploying ProductionPriceFeedConfig...");
        ProductionPriceFeedConfig priceFeedConfig = new ProductionPriceFeedConfig(priceOracle);
        result.priceFeedConfig = address(priceFeedConfig);
        console.log("ProductionPriceFeedConfig deployed at:", result.priceFeedConfig);
        
        // 4. Mine and deploy EigenLVRHook with valid address
        console.log("Mining valid hook address...");
        result.hookFlags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        
        (address hookAddress, bytes32 salt) = mineHookAddress(
            config,
            result.priceOracle,
            deployer,
            result.hookFlags
        );
        
        result.salt = salt;
        
        console.log("Deploying EigenLVRHook at mined address...");
        EigenLVRHook hook = new EigenLVRHook{salt: salt}(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            deployer, // Fee recipient
            config.lvrThreshold
        );
        
        result.hook = address(hook);
        require(result.hook == hookAddress, "Hook deployed at wrong address");
        console.log("EigenLVRHook deployed at:", result.hook);
        
        console.log("=== Phase 1 Complete ===\n");
    }
    
    function configureSystem(
        DeploymentResult memory result,
        DeploymentConfig memory config,
        address deployer
    ) internal {
        console.log("=== Phase 2: System Configuration ===");
        
        // Configure price feeds
        console.log("Configuring price feeds...");
        ProductionPriceFeedConfig(result.priceFeedConfig).autoConfigureNetwork();
        console.log("Price feeds configured for", getNetworkName());
        
        // Set up hook permissions
        console.log("Setting up initial operator authorization...");
        EigenLVRHook(result.hook).setOperatorAuthorization(deployer, true);
        EigenLVRHook(result.hook).setOperatorAuthorization(result.serviceManager, true);
        
        // Fund service manager for rewards
        console.log("Funding service manager...");
        EigenLVRAVSServiceManager(payable(result.serviceManager)).fundRewardPool{value: 1 ether}();
        
        // Transfer ownership where needed
        console.log("Configuring ownerships...");
        ProductionPriceFeedConfig(result.priceFeedConfig).transferOwnership(deployer);
        
        console.log("=== Phase 2 Complete ===\n");
    }
    
    function mineHookAddress(
        DeploymentConfig memory config,
        address priceOracle,
        address deployer,
        uint160 flags
    ) internal view returns (address hookAddress, bytes32 salt) {
        
        bytes memory constructorArgs = abi.encode(
            config.poolManager,
            config.avsDirectory,
            priceOracle,
            deployer, // Fee recipient
            config.lvrThreshold
        );
        
        (hookAddress, salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(EigenLVRHook).creationCode,
            constructorArgs
        );
        
        console.log("Hook address mined:", hookAddress);
        console.log("Required flags:", flags);
        console.log("Address flags:", uint160(hookAddress) & HookMiner.FLAG_MASK);
        console.log("Salt:", vm.toString(salt));
    }
    
    function getDeploymentConfig() internal view returns (DeploymentConfig memory) {
        uint256 chainId = block.chainid;
        
        if (chainId == 1) {
            // Mainnet
            return DeploymentConfig({
                poolManager: 0x0000000000000000000000000000000000000000, // Update with actual
                avsDirectory: 0x0000000000000000000000000000000000000000, // Update with actual
                delegationManager: 0x0000000000000000000000000000000000000000, // Update with actual
                lvrThreshold: 50, // 0.5%
                minimumStake: 32 ether
            });
        } else if (chainId == 11155111) {
            // Sepolia
            return DeploymentConfig({
                poolManager: 0x0000000000000000000000000000000000000000, // Update with actual
                avsDirectory: 0x0000000000000000000000000000000000000000, // Update with actual
                delegationManager: 0x0000000000000000000000000000000000000000, // Update with actual
                lvrThreshold: 100, // 1% for testnet (higher threshold)
                minimumStake: 1 ether // Lower stake for testnet
            });
        } else if (chainId == 8453) {
            // Base
            return DeploymentConfig({
                poolManager: 0x0000000000000000000000000000000000000000, // Update with actual
                avsDirectory: 0x0000000000000000000000000000000000000000, // Update with actual
                delegationManager: 0x0000000000000000000000000000000000000000, // Update with actual
                lvrThreshold: 75, // 0.75%
                minimumStake: 16 ether
            });
        } else {
            revert("Unsupported network");
        }
    }
    
    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        
        if (chainId == 1) return "Ethereum Mainnet";
        if (chainId == 11155111) return "Sepolia Testnet";
        if (chainId == 8453) return "Base";
        if (chainId == 42161) return "Arbitrum One";
        if (chainId == 31337) return "Localhost";
        
        return "Unknown Network";
    }
    
    function logDeploymentResults(
        DeploymentResult memory result,
        DeploymentConfig memory config
    ) internal view {
        console.log("\n=== Final Deployment Summary ===");
        console.log("Network:", getNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("Core Contracts:");
        console.log("- EigenLVRHook:", result.hook);
        console.log("- ChainlinkPriceOracle:", result.priceOracle);
        console.log("- EigenLVRAVSServiceManager:", result.serviceManager);
        console.log("- ProductionPriceFeedConfig:", result.priceFeedConfig);
        console.log("");
        console.log("Deployment Details:");
        console.log("- Salt:", vm.toString(result.salt));
        console.log("- Hook Flags:", result.hookFlags);
        console.log("- LVR Threshold:", config.lvrThreshold, "basis points");
        console.log("- Minimum Stake:", config.minimumStake / 1e18, "ETH");
        console.log("");
        console.log("Configuration:");
        console.log("- Hook Address Valid:", 
            (uint160(result.hook) & HookMiner.FLAG_MASK) == result.hookFlags);
        console.log("- Price Feeds Configured: Yes");
        console.log("- AVS Service Manager Ready: Yes");
        console.log("================================\n");
    }
    
    function saveDeploymentResults(
        DeploymentResult memory result,
        DeploymentConfig memory config
    ) internal {
        string memory deploymentInfo = string(abi.encodePacked(
            "# EigenLVR Complete Deployment - ", getNetworkName(), "\n\n",
            "**Deployment Date:** ", vm.toString(block.timestamp), "\n",
            "**Network:** ", getNetworkName(), "\n",
            "**Chain ID:** ", vm.toString(block.chainid), "\n\n",
            
            "## Contract Addresses\n\n",
            "| Contract | Address |\n",
            "|----------|----------|\n",
            "| EigenLVRHook | `", vm.toString(result.hook), "` |\n",
            "| ChainlinkPriceOracle | `", vm.toString(result.priceOracle), "` |\n",
            "| EigenLVRAVSServiceManager | `", vm.toString(result.serviceManager), "` |\n",
            "| ProductionPriceFeedConfig | `", vm.toString(result.priceFeedConfig), "` |\n\n",
            
            "## Configuration\n\n",
            "- **LVR Threshold:** ", vm.toString(config.lvrThreshold), " basis points (", 
            vm.toString(config.lvrThreshold / 100), ".0%)\n",
            "- **Minimum Operator Stake:** ", vm.toString(config.minimumStake / 1e18), " ETH\n",
            "- **Hook Permissions:** beforeAddLiquidity, beforeRemoveLiquidity, beforeSwap, afterSwap\n",
            "- **Hook Flags:** ", vm.toString(result.hookFlags), "\n",
            "- **Deployment Salt:** `", vm.toString(result.salt), "`\n\n",
            
            "## Verification\n\n",
            "- ✅ Hook Address Valid\n",
            "- ✅ Price Feeds Configured\n",
            "- ✅ AVS Service Manager Deployed\n",
            "- ✅ Initial Operators Authorized\n",
            "- ✅ System Ready for Production\n\n",
            
            "## Next Steps\n\n",
            "1. Register additional AVS operators\n",
            "2. Set up monitoring and alerting\n",
            "3. Configure frontend dashboard\n",
            "4. Begin LP onboarding\n"
        ));
        
        string memory filename = string(abi.encodePacked(
            "./deployments/",
            getNetworkName(),
            "_complete_",
            vm.toString(block.timestamp),
            ".md"
        ));
        
        vm.writeFile(filename, deploymentInfo);
        console.log("Complete deployment documentation saved to:", filename);
        
        // Also save as JSON for programmatic access
        string memory jsonData = string(abi.encodePacked(
            "{\n",
            '  "network": "', getNetworkName(), '",\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "timestamp": ', vm.toString(block.timestamp), ',\n',
            '  "contracts": {\n',
            '    "hook": "', vm.toString(result.hook), '",\n',
            '    "priceOracle": "', vm.toString(result.priceOracle), '",\n',
            '    "serviceManager": "', vm.toString(result.serviceManager), '",\n',
            '    "priceFeedConfig": "', vm.toString(result.priceFeedConfig), '"\n',
            '  },\n',
            '  "salt": "', vm.toString(result.salt), '",\n',
            '  "hookFlags": ', vm.toString(result.hookFlags), ',\n',
            '  "lvrThreshold": ', vm.toString(config.lvrThreshold), '\n',
            "}"
        ));
        
        string memory jsonFilename = string(abi.encodePacked(
            "./deployments/",
            getNetworkName(),
            "_deployment.json"
        ));
        
        vm.writeFile(jsonFilename, jsonData);
        console.log("Deployment data saved to:", jsonFilename);
    }
}