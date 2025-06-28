// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

contract MockPoolManager {
    function unlock(bytes calldata) external pure returns (bytes memory) { return ""; }
}

contract MockAVSDirectory is IAVSDirectory {
    mapping(address => mapping(address => bool)) public operatorRegistered;
    mapping(address => mapping(address => uint256)) public operatorStakes;
    
    function registerOperatorToAVS(address operator, bytes calldata) external override {
        operatorRegistered[msg.sender][operator] = true;
    }
    
    function deregisterOperatorFromAVS(address operator) external override {
        operatorRegistered[msg.sender][operator] = false;
    }
    
    function isOperatorRegistered(address avs, address operator) external view override returns (bool) {
        return operatorRegistered[avs][operator];
    }
    
    function getOperatorStake(address avs, address operator) external view override returns (uint256) {
        return operatorStakes[avs][operator];
    }
}

contract MockPriceOracle {
    function getPrice(address, address) external pure returns (uint256) {
        return 2000e18;
    }
}

contract HookDeploymentDebugTest is Test {
    uint160 public constant REQUIRED_FLAGS = 
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG |      // 1 << 11 = 2048
        Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |   // 1 << 9 = 512
        Hooks.BEFORE_SWAP_FLAG |               // 1 << 7 = 128
        Hooks.AFTER_SWAP_FLAG;                 // 1 << 6 = 64

    function test_DebugHookDeployment() public {
        address deployer = address(0x1234567890123456789012345678901234567890);
        
        MockPoolManager poolManager = new MockPoolManager();
        MockAVSDirectory avsDirectory = new MockAVSDirectory();
        MockPriceOracle priceOracle = new MockPriceOracle();
        address feeRecipient = address(0x4444444444444444444444444444444444444444);
        uint256 lvrThreshold = 50;
        
        console.log("Required flags:", REQUIRED_FLAGS);
        
        // Get contract creation code
        bytes memory creationCode = type(EigenLVRHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            IPoolManager(address(poolManager)),
            IAVSDirectory(address(avsDirectory)),
            IPriceOracle(address(priceOracle)),
            feeRecipient,
            lvrThreshold
        );
        
        console.log("Creation code length:", creationCode.length);
        console.log("Constructor args length:", constructorArgs.length);
        
        console.log("Mining hook address...");
        
        // Try to mine the address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployer,
            REQUIRED_FLAGS,
            creationCode,
            constructorArgs
        );
        
        console.log("Found hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));
        console.log("Address has required flags:", uint160(hookAddress) & REQUIRED_FLAGS == REQUIRED_FLAGS);
        
        // Now try to deploy with CREATE2
        vm.prank(deployer);
        EigenLVRHook hook = new EigenLVRHook{salt: salt}(
            IPoolManager(address(poolManager)),
            IAVSDirectory(address(avsDirectory)),
            IPriceOracle(address(priceOracle)),
            feeRecipient,
            lvrThreshold
        );
        
        console.log("Hook deployed at:", address(hook));
        console.log("Deployment matches mined address:", address(hook) == hookAddress);
        
        // Test if the deployed hook has the right permissions
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        console.log("beforeAddLiquidity:", permissions.beforeAddLiquidity);
        console.log("beforeRemoveLiquidity:", permissions.beforeRemoveLiquidity);
        console.log("beforeSwap:", permissions.beforeSwap);
        console.log("afterSwap:", permissions.afterSwap);
    }
}