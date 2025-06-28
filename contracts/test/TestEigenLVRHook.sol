// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

/**
 * @title Test version of EigenLVRHook that skips address validation
 * @notice This allows deployment to any address for testing purposes
 */
contract TestEigenLVRHook is EigenLVRHook {
    // Test variables to mock pool price
    mapping(bytes32 => uint256) public mockPoolPrices;
    
    constructor(
        IPoolManager _poolManager,
        IAVSDirectory _avsDirectory,
        IPriceOracle _priceOracle,
        address _feeRecipient,
        uint256 _lvrThreshold
    ) EigenLVRHook(
        _poolManager,
        _avsDirectory,
        _priceOracle,
        _feeRecipient,
        _lvrThreshold
    ) {}
    
    /// @dev Override to skip hook address validation during testing
    function validateHookAddress(BaseHook) internal pure override {
        // Skip validation for testing
    }
    
    /// @dev Set mock pool price for testing
    function setMockPoolPrice(PoolKey calldata key, uint256 price) external {
        bytes32 poolKey = keccak256(abi.encode(key.currency0, key.currency1, key.fee));
        mockPoolPrices[poolKey] = price;
    }
    
    /// @dev Override to return mock pool price if set
    function _getPoolPrice(PoolKey calldata key) internal view override returns (uint256) {
        bytes32 poolKey = keccak256(abi.encode(key.currency0, key.currency1, key.fee));
        uint256 mockPrice = mockPoolPrices[poolKey];
        if (mockPrice > 0) {
            return mockPrice;
        }
        // Fall back to parent implementation
        return super._getPoolPrice(key);
    }
    
    // Test wrapper functions that bypass the onlyPoolManager modifier
    function testBeforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4) {
        // Temporarily set the pool manager to this contract for testing
        return _beforeAddLiquidity(sender, key, params, hookData);
    }
    
    function testBeforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4) {
        return _beforeRemoveLiquidity(sender, key, params, hookData);
    }
    
    function testBeforeSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4, BeforeSwapDelta, uint24) {
        return _beforeSwap(sender, key, params, hookData);
    }
    
    function testAfterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128) {
        return _afterSwap(sender, key, params, delta, hookData);
    }
}