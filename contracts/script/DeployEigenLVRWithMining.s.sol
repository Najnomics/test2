// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

/**
 * @title DeployEigenLVRWithMining
 * @notice Production deployment script using CREATE2 address mining for valid hook addresses
 */
contract DeployEigenLVRWithMining is Script {
    // CREATE2 Deployer Proxy address (same on all networks)
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // Network-specific addresses
    struct NetworkConfig {
        address poolManager;
        address avsDirectory;
        address delegationManager;
        address ethUsdFeed;
        address usdcUsdFeed;
    }
    
    // Sepolia testnet addresses
    NetworkConfig public sepoliaConfig = NetworkConfig({
        poolManager: 0x0000000000000000000000000000000000000000, // Update with actual v4 pool manager
        avsDirectory: 0x0000000000000000000000000000000000000000, // Update with actual AVS directory
        delegationManager: 0x0000000000000000000000000000000000000000, // Update with actual delegation manager
        ethUsdFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH/USD on Sepolia
        usdcUsdFeed: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E // USDC/USD on Sepolia
    });
    
    // Mainnet addresses  
    NetworkConfig public mainnetConfig = NetworkConfig({
        poolManager: 0x0000000000000000000000000000000000000000, // Update with actual v4 pool manager
        avsDirectory: 0x0000000000000000000000000000000000000000, // Update with actual AVS directory
        delegationManager: 0x0000000000000000000000000000000000000000, // Update with actual delegation manager
        ethUsdFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // ETH/USD on Mainnet
        usdcUsdFeed: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6 // USDC/USD on Mainnet
    });
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== EigenLVR Hook Deployment with Address Mining ===");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Network:", getNetworkName());
        
        // Get network configuration
        NetworkConfig memory config = getNetworkConfig();
        
        // Calculate required hook permissions
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        
        console.log("Required hook flags:", flags);
        console.log("Mining hook address...");
        
        // Mine a valid hook address
        (address hookAddress, bytes32 salt) = mineHookAddress(config, flags);
        
        console.log("Found valid hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ChainlinkPriceOracle first
        console.log("Deploying ChainlinkPriceOracle...");
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle();
        console.log("ChainlinkPriceOracle deployed at:", address(priceOracle));
        
        // Deploy EigenLVRHook at the mined address
        console.log("Deploying EigenLVRHook at mined address...");
        EigenLVRHook hook = new EigenLVRHook{salt: salt}(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            deployer, // Fee recipient
            50 // LVR threshold (0.5%)
        );
        
        // Verify deployment address matches mined address
        require(address(hook) == hookAddress, "Hook deployed at wrong address");
        console.log("EigenLVRHook deployed at:", address(hook));
        
        // Configure price feeds
        console.log("Configuring price feeds...");
        setupPriceFeeds(priceOracle, config);
        
        // Set up initial operator authorization (deployer as initial operator)
        console.log("Setting up initial operator authorization...");
        hook.setOperatorAuthorization(deployer, true);
        
        vm.stopBroadcast();
        
        // Log deployment summary
        logDeploymentSummary(address(hook), address(priceOracle), hookAddress, salt);
        
        // Save deployment addresses
        saveDeploymentInfo(address(hook), address(priceOracle), hookAddress, salt);
    }
    
    function mineHookAddress(NetworkConfig memory config, uint160 flags) 
        internal 
        view 
        returns (address hookAddress, bytes32 salt) 
    {
        // Prepare constructor arguments
        bytes memory constructorArgs = abi.encode(
            config.poolManager,
            config.avsDirectory,
            address(0), // Placeholder for price oracle (will be deployed separately)
            vm.addr(vm.envUint("PRIVATE_KEY")), // Fee recipient
            50 // LVR threshold
        );
        
        // Mine the address
        (hookAddress, salt) = HookMiner.find(
            CREATE2_DEPLOYER,
            flags,
            type(EigenLVRHook).creationCode,
            constructorArgs
        );
        
        console.log("Address mining completed");
        console.log("- Required flags:", flags);
        console.log("- Found address:", hookAddress);
        console.log("- Address flags:", uint160(hookAddress) & HookMiner.FLAG_MASK);
        console.log("- Salt:", vm.toString(salt));
    }
    
    function setupPriceFeeds(ChainlinkPriceOracle priceOracle, NetworkConfig memory config) internal {
        // Example token addresses (update with actual token addresses for your pools)
        address WETH = getWETHAddress();
        address USDC = getUSDCAddress();
        
        if (config.ethUsdFeed != address(0)) {
            // Add ETH/USD price feed
            priceOracle.addPriceFeed(
                Currency.wrap(WETH),
                Currency.wrap(USDC),
                config.ethUsdFeed
            );
            console.log("Added ETH/USDC price feed:", config.ethUsdFeed);
        }
        
        if (config.usdcUsdFeed != address(0)) {
            // Add additional feeds as needed
            console.log("USDC/USD feed available:", config.usdcUsdFeed);
        }
    }
    
    function getNetworkConfig() internal view returns (NetworkConfig memory) {
        if (block.chainid == 11155111) {
            return sepoliaConfig;
        } else if (block.chainid == 1) {
            return mainnetConfig;
        } else {
            revert("Unsupported network");
        }
    }
    
    function getNetworkName() internal view returns (string memory) {
        if (block.chainid == 11155111) {
            return "Sepolia";
        } else if (block.chainid == 1) {
            return "Mainnet";
        } else if (block.chainid == 31337) {
            return "Localhost";
        } else {
            return "Unknown";
        }
    }
    
    function getWETHAddress() internal view returns (address) {
        if (block.chainid == 1) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // Mainnet WETH
        } else if (block.chainid == 11155111) {
            return 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // Sepolia WETH
        } else {
            return address(0);
        }
    }
    
    function getUSDCAddress() internal view returns (address) {
        if (block.chainid == 1) {
            return 0xA0b86a33E6441c4c27d3F50C9D6D14bDF12F4e6E; // Mainnet USDC
        } else if (block.chainid == 11155111) {
            return 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Sepolia USDC
        } else {
            return address(0);
        }
    }
    
    function logDeploymentSummary(
        address hook,
        address oracle,
        address expectedHookAddress,
        bytes32 salt
    ) internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", getNetworkName());
        console.log("ChainlinkPriceOracle:", oracle);
        console.log("EigenLVRHook:", hook);
        console.log("Expected Hook Address:", expectedHookAddress);
        console.log("Deployment Salt:", vm.toString(salt));
        console.log("Hook Flags Match:", (uint160(hook) & HookMiner.FLAG_MASK) == uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        ));
        console.log("Deployer:", vm.addr(vm.envUint("PRIVATE_KEY")));
        console.log("=========================\n");
    }
    
    function saveDeploymentInfo(
        address hook,
        address oracle,
        address expectedHookAddress,
        bytes32 salt
    ) internal {
        string memory deploymentInfo = string(abi.encodePacked(
            "# EigenLVR Deployment - ", getNetworkName(), "\n",
            "Date: ", vm.toString(block.timestamp), "\n",
            "Network: ", getNetworkName(), "\n",
            "Chain ID: ", vm.toString(block.chainid), "\n\n",
            "## Contract Addresses\n",
            "ChainlinkPriceOracle: ", vm.toString(oracle), "\n",
            "EigenLVRHook: ", vm.toString(hook), "\n",
            "Expected Hook Address: ", vm.toString(expectedHookAddress), "\n\n",
            "## Deployment Details\n",
            "Salt: ", vm.toString(salt), "\n",
            "Deployer: ", vm.toString(vm.addr(vm.envUint("PRIVATE_KEY"))), "\n",
            "Gas Used: ", vm.toString(gasleft()), "\n\n",
            "## Verification\n",
            "Hook Address Valid: ", vm.toString(hook == expectedHookAddress), "\n",
            "Hook Flags: ", vm.toString(uint160(hook) & HookMiner.FLAG_MASK), "\n"
        ));
        
        string memory filename = string(abi.encodePacked(
            "./deployments/",
            getNetworkName(),
            "_",
            vm.toString(block.timestamp),
            ".md"
        ));
        
        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);
    }
}

// Import Currency for type safety
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";