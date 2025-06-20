// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {ChainlinkPriceOracle} from "../src/ChainlinkPriceOracle.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

// Mock contracts for testing
contract MockPoolManager {
    function swap(
        PoolKey calldata /* key */,
        SwapParams calldata /* params */,
        bytes calldata /* hookData */
    ) external pure returns (bytes4) {
        return bytes4(0);
    }
}

contract MockAVSDirectory is IAVSDirectory {
    mapping(address => mapping(address => bool)) public operatorRegistered;
    
    function registerOperatorToAVS(address operator, bytes calldata) external override {
        operatorRegistered[msg.sender][operator] = true;
    }
    
    function deregisterOperatorFromAVS(address operator) external override {
        operatorRegistered[msg.sender][operator] = false;
    }
    
    function isOperatorRegistered(address avs, address operator) external view override returns (bool) {
        return operatorRegistered[avs][operator];
    }
    
    function getOperatorStake(address, address) external pure override returns (uint256) {
        return 1000 ether; // Mock stake
    }
}

contract MockPriceOracle is IPriceOracle {
    mapping(bytes32 => uint256) private prices;
    mapping(bytes32 => uint256) private updateTimes;
    
    function setPrice(Currency token0, Currency token1, uint256 price) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        prices[key] = price;
        updateTimes[key] = block.timestamp;
    }
    
    function getPrice(Currency token0, Currency token1) external view override returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        require(prices[key] != 0, "Price not set");
        return prices[key];
    }
    
    function getPriceAtTime(Currency token0, Currency token1, uint256) external view override returns (uint256) {
        return this.getPrice(token0, token1);
    }
    
    function isPriceStale(Currency, Currency) external pure override returns (bool) {
        return false;
    }
    
    function getLastUpdateTime(Currency token0, Currency token1) external view override returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        return updateTimes[key];
    }
}

// Test contract that bypasses hook validation for unit testing
contract EigenLVRHookSimplifiedTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    EigenLVRHook public hook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public lp = address(0x3);
    address public arbitrageur = address(0x4);
    address public feeRecipient = address(0x5);
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    uint256 public constant LVR_THRESHOLD = 50; // 0.5%
    
    function setUp() public {
        // Deploy mocks
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();
        
        // Set up pool key with no hooks for testing
        poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        poolId = poolKey.toId();
        
        // Deploy hook directly without address validation
        // Use CREATE2 with a known salt to deploy
        bytes32 salt = bytes32(uint256(1));
        
        vm.startPrank(owner);
        hook = new EigenLVRHook{salt: salt}(
            IPoolManager(address(poolManager)),
            avsDirectory,
            priceOracle,
            feeRecipient,
            LVR_THRESHOLD
        );
        
        // Set up initial state
        hook.setOperatorAuthorization(operator, true);
        vm.stopPrank();
        
        // Set initial price
        priceOracle.setPrice(token0, token1, 1e18);
        
        // Fund contracts
        vm.deal(address(hook), 100 ether);
        vm.deal(arbitrageur, 10 ether);
        vm.deal(lp, 10 ether);
    }
    
    function test_Constructor() public view {
        assertEq(address(hook.avsDirectory()), address(avsDirectory));
        assertEq(address(hook.priceOracle()), address(priceOracle));
        assertEq(hook.feeRecipient(), feeRecipient);
        assertEq(hook.lvrThreshold(), LVR_THRESHOLD);
        assertTrue(hook.authorizedOperators(operator));
    }
    
    function test_SetOperatorAuthorization() public {
        address newOperator = address(0x6);
        
        vm.prank(owner);
        hook.setOperatorAuthorization(newOperator, true);
        
        assertTrue(hook.authorizedOperators(newOperator));
        
        vm.prank(owner);
        hook.setOperatorAuthorization(newOperator, false);
        
        assertFalse(hook.authorizedOperators(newOperator));
    }
    
    function test_SetLVRThreshold() public {
        uint256 newThreshold = 100; // 1%
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        
        assertEq(hook.lvrThreshold(), newThreshold);
    }
    
    function test_SetLVRThreshold_TooHigh() public {
        vm.prank(owner);
        vm.expectRevert("EigenLVR: threshold too high");
        hook.setLVRThreshold(1001); // > 10%
    }
    
    function test_AddLiquidity() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        // Test the internal logic via direct access
        vm.prank(address(poolManager)); // Simulate pool manager call
        hook.beforeAddLiquidity(lp, poolKey, params, "");
        
        assertEq(hook.lpLiquidity(poolId, lp), 1000e18);
        assertEq(hook.totalLiquidity(poolId), 1000e18);
    }
    
    function test_RemoveLiquidity() public {
        // First add liquidity
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        vm.prank(address(poolManager));
        hook.beforeAddLiquidity(lp, poolKey, addParams, "");
        
        // Then remove some
        ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: -500e18,
            salt: bytes32(0)
        });
        
        vm.prank(address(poolManager));
        hook.beforeRemoveLiquidity(lp, poolKey, removeParams, "");
        
        assertEq(hook.lpLiquidity(poolId, lp), 500e18);
        assertEq(hook.totalLiquidity(poolId), 500e18);
    }
    
    function test_AuctionFlow() public {
        // Set up liquidity first
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        vm.prank(address(poolManager));
        hook.beforeAddLiquidity(lp, poolKey, params, "");
        
        // Set significant price deviation to trigger auction
        priceOracle.setPrice(token0, token1, 1.1e18); // 10% increase
        
        // Simulate beforeSwap to start auction
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18, // Significant swap
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(address(poolManager));
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertTrue(auctionId != bytes32(0));
        
        // Fast forward past auction duration
        vm.warp(block.timestamp + 13);
        
        // Submit auction result
        vm.prank(operator);
        hook.submitAuctionResult(auctionId, arbitrageur, 1 ether);
        
        // Check auction state
        (
            PoolId auctionPoolId,
            ,
            ,
            bool isActive,
            bool isComplete,
            address winner,
            uint256 winningBid,
        ) = hook.auctions(auctionId);
        
        assertEq(PoolId.unwrap(auctionPoolId), PoolId.unwrap(poolId));
        assertFalse(isActive);
        assertTrue(isComplete);
        assertEq(winner, arbitrageur);
        assertEq(winningBid, 1 ether);
    }
    
    function test_ClaimRewards() public {
        // Add liquidity first
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        vm.prank(address(poolManager));
        hook.beforeAddLiquidity(lp, poolKey, params, "");
        
        // Simulate rewards accumulation
        vm.deal(address(hook), 10 ether);
        
        // Manually set pool rewards for testing
        vm.store(
            address(hook),
            keccak256(abi.encode(poolId, uint256(4))), // poolRewards mapping slot
            bytes32(uint256(5 ether))
        );
        
        uint256 lpBalanceBefore = lp.balance;
        
        vm.prank(lp);
        hook.claimRewards(poolId);
        
        uint256 lpBalanceAfter = lp.balance;
        assertTrue(lpBalanceAfter > lpBalanceBefore);
    }
    
    function test_LVRDetectionBelowThreshold() public {
        // Set small price deviation (below threshold)
        priceOracle.setPrice(token0, token1, 1.001e18); // 0.1% increase
        
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(address(poolManager));
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertEq(auctionId, bytes32(0)); // No auction should be triggered
    }
    
    function test_NoAuctionForSmallSwap() public {
        // Set significant price deviation
        priceOracle.setPrice(token0, token1, 1.1e18); // 10% increase
        
        // But use small swap amount
        SwapParams memory swapParams = SwapParams({
            zeroForOne: true,
            amountSpecified: 0.1e18, // Small swap below threshold
            sqrtPriceLimitX96: 0
        });
        
        vm.prank(address(poolManager));
        hook.beforeSwap(address(this), poolKey, swapParams, "");
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertEq(auctionId, bytes32(0)); // No auction should be triggered
    }
    
    function test_GetHookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeAddLiquidity);
        assertTrue(permissions.beforeRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
    }
    
    function test_ReceiveETH() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = address(hook).balance;
        
        (bool success, ) = address(hook).call{value: amount}("");
        assertTrue(success);
        
        assertEq(address(hook).balance, balanceBefore + amount);
    }
}