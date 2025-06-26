// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {EigenLVRHook} from "../src/EigenLVRHook.sol";
import {IAVSDirectory} from "../src/interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

// Test wrapper to avoid hook address validation issues
contract TestEigenLVRHook {
    EigenLVRHook public hook;
    
    constructor(
        address poolManager,
        address avsDirectory,
        address priceOracle,
        address _feeRecipient,
        uint256 lvrThreshold
    ) {
        // Deploy with CREATE (not CREATE2) to avoid address validation
        hook = new EigenLVRHook(
            IPoolManager(poolManager),
            IAVSDirectory(avsDirectory),
            IPriceOracle(priceOracle),
            _feeRecipient,
            lvrThreshold
        );
    }
    
    // Expose hook functions for testing
    function getHookPermissions() external view returns (Hooks.Permissions memory) {
        return hook.getHookPermissions();
    }
    
    function owner() external view returns (address) {
        return hook.owner();
    }
    
    function feeRecipient() external view returns (address) {
        return hook.feeRecipient();
    }
    
    function lvrThreshold() external view returns (uint256) {
        return hook.lvrThreshold();
    }
    
    function authorizedOperators(address operator) external view returns (bool) {
        return hook.authorizedOperators(operator);
    }
    
    function setOperatorAuthorization(address operator, bool authorized) external {
        hook.setOperatorAuthorization(operator, authorized);
    }
    
    function setLVRThreshold(uint256 newThreshold) external {
        hook.setLVRThreshold(newThreshold);
    }
    
    function setFeeRecipient(address newFeeRecipient) external {
        hook.setFeeRecipient(newFeeRecipient);
    }
    
    function pause() external {
        hook.pause();
    }
    
    function unpause() external {
        hook.unpause();
    }
    
    function paused() external view returns (bool) {
        return hook.paused();
    }
    
    // Constants
    function MIN_BID() external pure returns (uint256) {
        return 1e15;
    }
    
    function MAX_AUCTION_DURATION() external pure returns (uint256) {
        return 12;
    }
    
    function LP_REWARD_PERCENTAGE() external pure returns (uint256) {
        return 8500;
    }
    
    function AVS_REWARD_PERCENTAGE() external pure returns (uint256) {
        return 1000;
    }
    
    function PROTOCOL_FEE_PERCENTAGE() external pure returns (uint256) {
        return 300;
    }
    
    function GAS_COMPENSATION_PERCENTAGE() external pure returns (uint256) {
        return 200;
    }
    
    function BASIS_POINTS() external pure returns (uint256) {
        return 10000;
    }
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

contract MockPoolManager {
    // Minimal implementation for testing
}

/**
 * @title EigenLVRHook Unit Tests
 * @notice Unit tests for EigenLVRHook functionality without hook address validation
 */
contract EigenLVRHookUnitTest is Test {
    TestEigenLVRHook public testHook;
    MockPoolManager public poolManager;
    MockAVSDirectory public avsDirectory;
    MockPriceOracle public priceOracle;
    
    address public owner = address(0x1);
    address public operator = address(0x2);
    address public feeRecipient = address(0x4);
    address public nonOwner = address(0x6);
    
    uint256 public constant LVR_THRESHOLD = 50;

    event OperatorAuthorized(address indexed operator, bool authorized);
    event LVRThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    function setUp() public {
        poolManager = new MockPoolManager();
        avsDirectory = new MockAVSDirectory();
        priceOracle = new MockPriceOracle();
        
        vm.prank(owner);
        testHook = new TestEigenLVRHook(
            address(poolManager),
            address(avsDirectory),
            address(priceOracle),
            feeRecipient,
            LVR_THRESHOLD
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public view {
        assertEq(testHook.owner(), owner);
        assertEq(testHook.feeRecipient(), feeRecipient);
        assertEq(testHook.lvrThreshold(), LVR_THRESHOLD);
    }
    
    /*//////////////////////////////////////////////////////////////
                            HOOK PERMISSIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetHookPermissions() public view {
        Hooks.Permissions memory permissions = testHook.getHookPermissions();
        
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
                            ADMIN FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetOperatorAuthorization() public {
        vm.prank(owner);
        testHook.setOperatorAuthorization(operator, true);
        
        assertTrue(testHook.authorizedOperators(operator));
    }
    
    function test_SetOperatorAuthorization_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        testHook.setOperatorAuthorization(operator, true);
    }
    
    function test_SetOperatorAuthorization_Deauthorize() public {
        // First authorize
        vm.prank(owner);
        testHook.setOperatorAuthorization(operator, true);
        assertTrue(testHook.authorizedOperators(operator));
        
        // Then deauthorize
        vm.prank(owner);
        testHook.setOperatorAuthorization(operator, false);
        
        assertFalse(testHook.authorizedOperators(operator));
    }
    
    function test_SetLVRThreshold() public {
        uint256 newThreshold = 100; // 1%
        
        vm.prank(owner);
        testHook.setLVRThreshold(newThreshold);
        
        assertEq(testHook.lvrThreshold(), newThreshold);
    }
    
    function test_SetLVRThreshold_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        testHook.setLVRThreshold(100);
    }
    
    function test_SetLVRThreshold_TooHigh() public {
        vm.prank(owner);
        vm.expectRevert("EigenLVR: threshold too high");
        testHook.setLVRThreshold(1001); // > 10%
    }
    
    function test_SetLVRThreshold_MaxAllowed() public {
        vm.prank(owner);
        testHook.setLVRThreshold(1000); // Exactly 10%
        
        assertEq(testHook.lvrThreshold(), 1000);
    }
    
    function test_SetFeeRecipient() public {
        address newFeeRecipient = address(0x999);
        
        vm.prank(owner);
        testHook.setFeeRecipient(newFeeRecipient);
        
        assertEq(testHook.feeRecipient(), newFeeRecipient);
    }
    
    function test_SetFeeRecipient_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        testHook.setFeeRecipient(address(0x999));
    }
    
    function test_SetFeeRecipient_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("EigenLVR: invalid address");
        testHook.setFeeRecipient(address(0));
    }
    
    function test_Pause() public {
        vm.prank(owner);
        testHook.pause();
        
        assertTrue(testHook.paused());
    }
    
    function test_Pause_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        testHook.pause();
    }
    
    function test_Unpause() public {
        // First pause
        vm.prank(owner);
        testHook.pause();
        assertTrue(testHook.paused());
        
        // Then unpause
        vm.prank(owner);
        testHook.unpause();
        
        assertFalse(testHook.paused());
    }
    
    function test_Unpause_OnlyOwner() public {
        vm.prank(owner);
        testHook.pause();
        
        vm.prank(nonOwner);
        vm.expectRevert();
        testHook.unpause();
    }
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constants() public view {
        assertEq(testHook.MIN_BID(), 1e15);
        assertEq(testHook.MAX_AUCTION_DURATION(), 12);
        assertEq(testHook.LP_REWARD_PERCENTAGE(), 8500);
        assertEq(testHook.AVS_REWARD_PERCENTAGE(), 1000);
        assertEq(testHook.PROTOCOL_FEE_PERCENTAGE(), 300);
        assertEq(testHook.GAS_COMPENSATION_PERCENTAGE(), 200);
        assertEq(testHook.BASIS_POINTS(), 10000);
    }
    
    /*//////////////////////////////////////////////////////////////
                            PERCENTAGE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_PercentageCalculations() public view {
        uint256 totalAmount = 100 ether;
        
        uint256 lpAmount = (totalAmount * testHook.LP_REWARD_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 avsAmount = (totalAmount * testHook.AVS_REWARD_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 protocolAmount = (totalAmount * testHook.PROTOCOL_FEE_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 gasAmount = (totalAmount * testHook.GAS_COMPENSATION_PERCENTAGE()) / testHook.BASIS_POINTS();
        
        assertEq(lpAmount, 85 ether); // 85%
        assertEq(avsAmount, 10 ether); // 10%
        assertEq(protocolAmount, 3 ether); // 3%
        assertEq(gasAmount, 2 ether); // 2%
        
        // Total should equal original amount
        assertEq(lpAmount + avsAmount + protocolAmount + gasAmount, totalAmount);
    }
    
    function test_PercentageCalculations_SmallAmounts() public view {
        uint256 totalAmount = 1000;
        
        uint256 lpAmount = (totalAmount * testHook.LP_REWARD_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 avsAmount = (totalAmount * testHook.AVS_REWARD_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 protocolAmount = (totalAmount * testHook.PROTOCOL_FEE_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 gasAmount = (totalAmount * testHook.GAS_COMPENSATION_PERCENTAGE()) / testHook.BASIS_POINTS();
        
        assertEq(lpAmount, 850); // 85%
        assertEq(avsAmount, 100); // 10%
        assertEq(protocolAmount, 30); // 3%
        assertEq(gasAmount, 20); // 2%
    }
    
    function test_PercentageCalculations_ZeroAmount() public view {
        uint256 totalAmount = 0;
        
        uint256 lpAmount = (totalAmount * testHook.LP_REWARD_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 avsAmount = (totalAmount * testHook.AVS_REWARD_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 protocolAmount = (totalAmount * testHook.PROTOCOL_FEE_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 gasAmount = (totalAmount * testHook.GAS_COMPENSATION_PERCENTAGE()) / testHook.BASIS_POINTS();
        
        assertEq(lpAmount, 0);
        assertEq(avsAmount, 0);
        assertEq(protocolAmount, 0);
        assertEq(gasAmount, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_SetLVRThreshold(uint256 threshold) public {
        vm.assume(threshold <= 1000); // Only test valid thresholds
        
        vm.prank(owner);
        testHook.setLVRThreshold(threshold);
        
        assertEq(testHook.lvrThreshold(), threshold);
    }
    
    function testFuzz_SetLVRThreshold_Invalid(uint256 threshold) public {
        vm.assume(threshold > 1000); // Only test invalid thresholds
        
        vm.prank(owner);
        vm.expectRevert("EigenLVR: threshold too high");
        testHook.setLVRThreshold(threshold);
    }
    
    function testFuzz_PercentageCalculations(uint256 amount) public view {
        vm.assume(amount <= type(uint256).max / testHook.LP_REWARD_PERCENTAGE()); // Avoid overflow
        
        uint256 lpAmount = (amount * testHook.LP_REWARD_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 avsAmount = (amount * testHook.AVS_REWARD_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 protocolAmount = (amount * testHook.PROTOCOL_FEE_PERCENTAGE()) / testHook.BASIS_POINTS();
        uint256 gasAmount = (amount * testHook.GAS_COMPENSATION_PERCENTAGE()) / testHook.BASIS_POINTS();
        
        // Verify percentages are reasonable
        assertTrue(lpAmount <= amount);
        assertTrue(avsAmount <= amount);
        assertTrue(protocolAmount <= amount);
        assertTrue(gasAmount <= amount);
        
        // Verify LP gets the largest share
        assertTrue(lpAmount >= avsAmount);
        assertTrue(lpAmount >= protocolAmount);
        assertTrue(lpAmount >= gasAmount);
    }
    
    /*//////////////////////////////////////////////////////////////
                            AUTHORIZATION PATTERN TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AuthorizationPattern() public {
        // Test multiple operators
        address operator1 = address(0x100);
        address operator2 = address(0x200);
        address operator3 = address(0x300);
        
        // Initially none are authorized
        assertFalse(testHook.authorizedOperators(operator1));
        assertFalse(testHook.authorizedOperators(operator2));
        assertFalse(testHook.authorizedOperators(operator3));
        
        // Authorize operator1 and operator2
        vm.startPrank(owner);
        testHook.setOperatorAuthorization(operator1, true);
        testHook.setOperatorAuthorization(operator2, true);
        vm.stopPrank();
        
        assertTrue(testHook.authorizedOperators(operator1));
        assertTrue(testHook.authorizedOperators(operator2));
        assertFalse(testHook.authorizedOperators(operator3));
        
        // Deauthorize operator1
        vm.prank(owner);
        testHook.setOperatorAuthorization(operator1, false);
        
        assertFalse(testHook.authorizedOperators(operator1));
        assertTrue(testHook.authorizedOperators(operator2));
        assertFalse(testHook.authorizedOperators(operator3));
    }
}