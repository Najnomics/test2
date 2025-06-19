// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";

/**
 * @title DeployEigenLVR
 * @notice Deployment script for EigenLVR Hook and related contracts
 */
contract DeployEigenLVR is Script {
    // Network-specific addresses
    struct NetworkConfig {
        address poolManager;
        address avsDirectory;
        address delegationManager;
    }
    
    // Sepolia testnet addresses
    NetworkConfig public sepoliaConfig = NetworkConfig({
        poolManager: 0x0000000000000000000000000000000000000000, // Update with actual address
        avsDirectory: 0x0000000000000000000000000000000000000000, // Update with actual address
        delegationManager: 0x0000000000000000000000000000000000000000 // Update with actual address
    });
    
    // Mainnet addresses
    NetworkConfig public mainnetConfig = NetworkConfig({
        poolManager: 0x0000000000000000000000000000000000000000, // Update with actual address
        avsDirectory: 0x0000000000000000000000000000000000000000, // Update with actual address
        delegationManager: 0x0000000000000000000000000000000000000000 // Update with actual address
    });
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying contracts with deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Get network configuration
        NetworkConfig memory config = getNetworkConfig();
        
        // Deploy ChainlinkPriceOracle
        console.log("Deploying ChainlinkPriceOracle...");
        ChainlinkPriceOracle priceOracle = new ChainlinkPriceOracle();
        console.log("ChainlinkPriceOracle deployed at:", address(priceOracle));
        
        // Deploy EigenLVRHook
        console.log("Deploying EigenLVRHook...");
        EigenLVRHook hook = new EigenLVRHook(
            IPoolManager(config.poolManager),
            IAVSDirectory(config.avsDirectory),
            priceOracle,
            deployer, // Fee recipient
            50 // LVR threshold (0.5%)
        );
        console.log("EigenLVRHook deployed at:", address(hook));
        
        // Setup initial configuration
        console.log("Setting up initial configuration...");
        
        // Add price feeds (example for ETH/USDC)
        if (block.chainid == 11155111) { // Sepolia
            // Add Sepolia price feeds
            address ethUsdFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // ETH/USD on Sepolia
            // Note: You'll need to convert this to ETH/USDC or find appropriate feeds
            // priceOracle.addPriceFeed(token0, token1, ethUsdFeed);
        } else if (block.chainid == 1) { // Mainnet
            // Add mainnet price feeds
            address ethUsdFeed = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // ETH/USD on Mainnet
            // priceOracle.addPriceFeed(token0, token1, ethUsdFeed);
        }
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("=== Deployment Summary ===");
        console.log("Network:", getNetworkName());
        console.log("ChainlinkPriceOracle:", address(priceOracle));
        console.log("EigenLVRHook:", address(hook));
        console.log("Deployer:", deployer);
        console.log("========================");
        
        // Save deployment info to file
        string memory deploymentInfo = string(abi.encodePacked(
            "# EigenLVR Deployment\n",
            "Network: ", getNetworkName(), "\n",
            "ChainlinkPriceOracle: ", vm.toString(address(priceOracle)), "\n",
            "EigenLVRHook: ", vm.toString(address(hook)), "\n",
            "Deployer: ", vm.toString(deployer), "\n"
        ));
        
        vm.writeFile("./deployments/latest.txt", deploymentInfo);
        console.log("Deployment info saved to ./deployments/latest.txt");
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
}