// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {AuctionLib} from "../src/libraries/AuctionLib.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {HookMiner} from "../src/utils/HookMiner.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

// Mock contracts for testing
contract MockPoolManager {
    function unlock(bytes calldata) external pure returns (bytes memory) {
        return "";
    }
    function initialize(PoolKey memory, uint160) external pure returns (int24) {
        return 0;
    }
    function modifyLiquidity(PoolKey memory, ModifyLiquidityParams memory, bytes calldata) 
        external pure returns (BalanceDelta, BalanceDelta) {
        return (BalanceDelta.wrap(0), BalanceDelta.wrap(0));
    }
    function swap(PoolKey memory, SwapParams memory, bytes calldata) 
        external pure returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }
    function donate(PoolKey memory, uint256, uint256, bytes calldata) 
        external pure returns (BalanceDelta) {
        return BalanceDelta.wrap(0);
    }
    function sync(Currency) external pure {}
    function take(Currency, address, uint256) external pure {}
    function settle(Currency) external payable returns (uint256) {
        return 0;
    }
    function settleFor(Currency, address) external payable returns (uint256) {
        return 0;
    }
    function clear(Currency, uint256) external pure {}
    function mint(address, uint256, uint256) external pure {}
    function burn(address, uint256, uint256) external pure {}
    function updateDynamicLPFee(PoolKey memory, uint24) external pure {}
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
    
    function setOperatorStake(address avs, address operator, uint256 stake) external {
        operatorStakes[avs][operator] = stake;
    }
}

contract MockPriceOracle {
    mapping(bytes32 => uint256) public prices;
    mapping(bytes32 => bool) public stalePrices;
    
    function getPrice(Currency token0, Currency token1) external view returns (uint256) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        uint256 price = prices[key];
        return price > 0 ? price : 2000e18; // Default price 2000 USD
    }
    
    function setPrice(Currency token0, Currency token1, uint256 price) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        prices[key] = price;
    }
    
    function isPriceStale(Currency token0, Currency token1) external view returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        return stalePrices[key];
    }
    
    function setPriceStale(Currency token0, Currency token1, bool stale) external {
        bytes32 key = keccak256(abi.encodePacked(token0, token1));
        stalePrices[key] = stale;
    }
    
    function getLastUpdateTime(Currency, Currency) external view returns (uint256) {
        return block.timestamp;
    }
    
    function getPriceAtTime(Currency token0, Currency token1, uint256) external view returns (uint256) {
        return this.getPrice(token0, token1);
    }
}

/**
 * @title Fixed EigenLVRHook Tests with Proper Hook Address Mining
 * @notice Tests all EigenLVRHook functions with valid hook addresses
 */
contract EigenLVRHookFixedTest is Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    EigenLVRHook public hook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public lp = address(0x3);
    address public feeRecipient = address(0x4);
    address public user = address(0x5);
    
    Currency public token0 = Currency.wrap(address(0x100));
    Currency public token1 = Currency.wrap(address(0x200));
    
    PoolKey public poolKey;
    PoolId public poolId;
    
    uint256 public constant LVR_THRESHOLD = 50; // 0.5%

    function setUp() public {
        // Deploy mock contracts
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();
        
        // Mine a valid hook address
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG
        );
        
        // Create bytecode for hook deployment
        bytes memory constructorArgs = abi.encode(
            address(poolManager),
            address(avsDirectory),
            address(priceOracle),
            feeRecipient,
            LVR_THRESHOLD
        );
        
        bytes memory creationCode = type(EigenLVRHook).creationCode;
        
        // Find valid address
        (address hookAddress, bytes32 salt) = HookMiner.find(
            address(this),
            flags,
            creationCode,
            constructorArgs
        );
        
        // Deploy hook at the mined address
        vm.prank(owner);
        hook = new EigenLVRHook{salt: salt}(
            IPoolManager(address(poolManager)),
            avsDirectory,
            IPriceOracle(address(priceOracle)),
            feeRecipient,
            LVR_THRESHOLD
        );
        
        // Verify the hook address is correct
        assertEq(address(hook), hookAddress);
        
        // Set up pool key
        poolKey = PoolKey({
            currency0: token0,
            currency1: token1,
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        poolId = poolKey.toId();
        
        // Fund accounts
        vm.deal(address(hook), 100 ether);
        vm.deal(lp, 10 ether);
        vm.deal(user, 10 ether);
        vm.deal(operator, 5 ether);
        vm.deal(feeRecipient, 1 ether);
        
        // Set up oracle price
        priceOracle.setPrice(token0, token1, 2000e18);
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public view {
        assertEq(address(hook.avsDirectory()), address(avsDirectory));
        assertEq(address(hook.priceOracle()), address(priceOracle));
        assertEq(hook.feeRecipient(), feeRecipient);
        assertEq(hook.lvrThreshold(), LVR_THRESHOLD);
        assertEq(hook.owner(), owner);
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetHookPermissions() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertTrue(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertTrue(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
        assertFalse(permissions.beforeSwapReturnDelta);
        assertFalse(permissions.afterSwapReturnDelta);
        assertFalse(permissions.afterAddLiquidityReturnDelta);
        assertFalse(permissions.afterRemoveLiquidityReturnDelta);
    }
    
    /*//////////////////////////////////////////////////////////////
                            LIQUIDITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BeforeAddLiquidity() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        
        bytes4 selector = hook.beforeAddLiquidity(lp, poolKey, params, "");
        
        assertEq(selector, hook.beforeAddLiquidity.selector);
        assertEq(hook.lpLiquidity(poolId, lp), 1000e18);
        assertEq(hook.totalLiquidity(poolId), 1000e18);
    }
    
    function test_BeforeAddLiquidity_ZeroLiquidity() public {
        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 0,
            salt: bytes32(0)
        });
        
        hook.beforeAddLiquidity(lp, poolKey, params, "");
        
        assertEq(hook.lpLiquidity(poolId, lp), 0);
        assertEq(hook.totalLiquidity(poolId), 0);
    }
    
    function test_BeforeRemoveLiquidity() public {
        // First add liquidity
        ModifyLiquidityParams memory addParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: 1000e18,
            salt: bytes32(0)
        });
        hook.beforeAddLiquidity(lp, poolKey, addParams, "");
        
        // Then remove liquidity
        ModifyLiquidityParams memory removeParams = ModifyLiquidityParams({
            tickLower: -60,
            tickUpper: 60,
            liquidityDelta: -500e18,
            salt: bytes32(0)
        });
        
        bytes4 selector = hook.beforeRemoveLiquidity(lp, poolKey, removeParams, "");
        
        assertEq(selector, hook.beforeRemoveLiquidity.selector);
        assertEq(hook.lpLiquidity(poolId, lp), 500e18);
        assertEq(hook.totalLiquidity(poolId), 500e18);
    }
    
    /*//////////////////////////////////////////////////////////////
                            SWAP TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BeforeSwap_NoAuctionTrigger() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e17, // Small amount
            sqrtPriceLimitX96: 0
        });
        
        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = hook.beforeSwap(
            user, poolKey, params, ""
        );
        
        assertEq(selector, hook.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(delta), BeforeSwapDelta.unwrap(BeforeSwapDeltaLibrary.ZERO_DELTA));
        assertEq(fee, 0);
        
        // No auction should be active
        assertEq(hook.activeAuctions(poolId), bytes32(0));
    }
    
    function test_BeforeSwap_TriggerAuction() public {
        // Set up conditions for auction trigger (significant swap + price deviation)
        priceOracle.setPrice(token0, token1, 2100e18); // 5% price deviation
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18, // Significant amount
            sqrtPriceLimitX96: 0
        });
        
        hook.beforeSwap(user, poolKey, params, "");
        
        // Auction should be active
        bytes32 auctionId = hook.activeAuctions(poolId);
        assertTrue(auctionId != bytes32(0));
    }
    
    function test_BeforeSwap_Paused() public {
        vm.prank(owner);
        hook.pause();
        
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        vm.expectRevert();
        hook.beforeSwap(user, poolKey, params, "");
    }
    
    function test_AfterSwap_NoActiveAuction() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });
        
        (bytes4 selector, int128 delta) = hook.afterSwap(
            user, poolKey, params, BalanceDelta.wrap(0), ""
        );
        
        assertEq(selector, hook.afterSwap.selector);
        assertEq(delta, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetOperatorAuthorization() public {
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        assertTrue(hook.authorizedOperators(operator));
    }
    
    function test_SetLVRThreshold() public {
        uint256 newThreshold = 100; // 1%
        
        vm.prank(owner);
        hook.setLVRThreshold(newThreshold);
        
        assertEq(hook.lvrThreshold(), newThreshold);
    }
    
    function test_SetLVRThreshold_TooHigh() public {
        uint256 newThreshold = 1100; // 11% - too high
        
        vm.prank(owner);
        vm.expectRevert("EigenLVR: threshold too high");
        hook.setLVRThreshold(newThreshold);
    }
    
    function test_Pause() public {
        vm.prank(owner);
        hook.pause();
        
        assertTrue(hook.paused());
    }
    
    function test_Unpause() public {
        vm.prank(owner);
        hook.pause();
        
        vm.prank(owner);
        hook.unpause();
        
        assertFalse(hook.paused());
    }
    
    /*//////////////////////////////////////////////////////////////
                            AUCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SubmitAuctionResult() public {
        // First create an auction
        _createAuction();
        
        bytes32 auctionId = hook.activeAuctions(poolId);
        
        // Authorize operator
        vm.prank(owner);
        hook.setOperatorAuthorization(operator, true);
        
        // Fast forward past auction end
        vm.warp(block.timestamp + hook.MAX_AUCTION_DURATION() + 1);
        
        address winner = address(0x777);
        uint256 winningBid = 5 ether;
        
        vm.prank(operator);
        hook.submitAuctionResult(auctionId, winner, winningBid);
        
        // Check auction state
        (,,,, bool isComplete, address auctionWinner, uint256 bid,) = hook.auctions(auctionId);
        assertTrue(isComplete);
        assertEq(auctionWinner, winner);
        assertEq(bid, winningBid);
    }
    
    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createAuction() internal {
        // Create auction by triggering a swap
        priceOracle.setPrice(token0, token1, 2100e18); // 5% deviation
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 2e18,
            sqrtPriceLimitX96: 0
        });
        hook.beforeSwap(user, poolKey, params, "");
    }
}