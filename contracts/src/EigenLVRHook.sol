// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/contracts/types/BeforeSwapDelta.sol";
import {BaseHook} from "@uniswap/v4-periphery/contracts/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IAVSDirectory} from "./interfaces/IAVSDirectory.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {AuctionLib} from "./libraries/AuctionLib.sol";

/**
 * @title EigenLVRHook
 * @author EigenLVR Team
 * @notice A Uniswap v4 Hook that mitigates Loss Versus Rebalancing (LVR) through 
 *         EigenLayer-powered sealed-bid auctions
 * @dev This hook intercepts swaps to run block-level auctions, redistributing MEV to LPs
 */
contract EigenLVRHook is BaseHook, ReentrancyGuard, Ownable, Pausable {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using AuctionLib for AuctionLib.Auction;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Minimum bid amount (0.001 ETH)
    uint256 public constant MIN_BID = 1e15;
    
    /// @notice Maximum auction duration in seconds
    uint256 public constant MAX_AUCTION_DURATION = 12;
    
    /// @notice LP reward percentage (85%)
    uint256 public constant LP_REWARD_PERCENTAGE = 8500;
    
    /// @notice AVS operator reward percentage (10%)
    uint256 public constant AVS_REWARD_PERCENTAGE = 1000;
    
    /// @notice Protocol fee percentage (3%)
    uint256 public constant PROTOCOL_FEE_PERCENTAGE = 300;
    
    /// @notice Gas compensation percentage (2%)
    uint256 public constant GAS_COMPENSATION_PERCENTAGE = 200;
    
    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice EigenLayer AVS Directory for operator validation
    IAVSDirectory public immutable avsDirectory;
    
    /// @notice Price oracle for LVR detection
    IPriceOracle public immutable priceOracle;
    
    /// @notice Mapping of pool to active auctions
    mapping(PoolId => bytes32) public activeAuctions;
    
    /// @notice Mapping of auction ID to auction data
    mapping(bytes32 => AuctionLib.Auction) public auctions;
    
    /// @notice Mapping of pool to accumulated LP rewards
    mapping(PoolId => uint256) public poolRewards;
    
    /// @notice Mapping of LP to claimable rewards per pool
    mapping(PoolId => mapping(address => uint256)) public lpRewards;
    
    /// @notice Mapping of pool to total liquidity (for reward calculation)
    mapping(PoolId => uint256) public totalLiquidity;
    
    /// @notice Mapping of pool to LP liquidity positions
    mapping(PoolId => mapping(address => uint256)) public lpLiquidity;
    
    /// @notice Authorized AVS operators
    mapping(address => bool) public authorizedOperators;
    
    /// @notice Protocol fee recipient
    address public feeRecipient;
    
    /// @notice LVR threshold for triggering auctions (in basis points)
    uint256 public lvrThreshold;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event AuctionStarted(
        bytes32 indexed auctionId,
        PoolId indexed poolId,
        uint256 startTime,
        uint256 duration
    );
    
    event AuctionEnded(
        bytes32 indexed auctionId,
        PoolId indexed poolId,
        address indexed winner,
        uint256 winningBid
    );
    
    event MEVDistributed(
        PoolId indexed poolId,
        uint256 totalAmount,
        uint256 lpAmount,
        uint256 avsAmount,
        uint256 protocolAmount
    );
    
    event RewardsClaimed(
        PoolId indexed poolId,
        address indexed lp,
        uint256 amount
    );
    
    event OperatorAuthorized(address indexed operator, bool authorized);
    
    event LVRThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorizedOperator() {
        require(authorizedOperators[msg.sender], "EigenLVR: unauthorized operator");
        _;
    }
    
    modifier onlyActiveAuction(bytes32 auctionId) {
        require(auctions[auctionId].isActive, "EigenLVR: auction not active");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        IPoolManager _poolManager,
        IAVSDirectory _avsDirectory,
        IPriceOracle _priceOracle,
        address _feeRecipient,
        uint256 _lvrThreshold
    ) BaseHook(_poolManager) Ownable(msg.sender) {
        avsDirectory = _avsDirectory;
        priceOracle = _priceOracle;
        feeRecipient = _feeRecipient;
        lvrThreshold = _lvrThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Returns the hook's permissions
     */
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
    
    /**
     * @notice Called before adding liquidity to track LP positions
     */
    function beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override onlyByPoolManager returns (bytes4) {
        PoolId poolId = key.toId();
        
        // Update LP liquidity tracking
        if (params.liquidityDelta > 0) {
            lpLiquidity[poolId][sender] += uint256(int256(params.liquidityDelta));
            totalLiquidity[poolId] += uint256(int256(params.liquidityDelta));
        }
        
        return this.beforeAddLiquidity.selector;
    }
    
    /**
     * @notice Called before removing liquidity to update LP positions
     */
    function beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata
    ) external override onlyByPoolManager returns (bytes4) {
        PoolId poolId = key.toId();
        
        // Update LP liquidity tracking
        if (params.liquidityDelta < 0) {
            uint256 liquidityRemoved = uint256(-int256(params.liquidityDelta));
            lpLiquidity[poolId][sender] -= liquidityRemoved;
            totalLiquidity[poolId] -= liquidityRemoved;
        }
        
        return this.beforeRemoveLiquidity.selector;
    }
    
    /**
     * @notice Called before swap to potentially trigger LVR auction
     */
    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata
    ) external override onlyByPoolManager whenNotPaused returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();
        
        // Check if LVR threshold is exceeded
        if (_shouldTriggerAuction(key, params)) {
            _startAuction(poolId);
        }
        
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
    
    /**
     * @notice Called after swap to handle auction results and distribute MEV
     */
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override onlyByPoolManager returns (bytes4, int128) {
        PoolId poolId = key.toId();
        bytes32 auctionId = activeAuctions[poolId];
        
        // Process completed auction if exists
        if (auctionId != bytes32(0) && auctions[auctionId].isComplete) {
            _processAuctionResult(poolId, auctionId);
        }
        
        return (this.afterSwap.selector, 0);
    }

    /*//////////////////////////////////////////////////////////////
                           AUCTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Start a new auction for a pool
     * @param poolId The pool ID to auction
     */
    function _startAuction(PoolId poolId) internal {
        bytes32 auctionId = keccak256(abi.encodePacked(poolId, block.timestamp, block.number));
        
        // Ensure no active auction exists
        require(activeAuctions[poolId] == bytes32(0), "EigenLVR: auction already active");
        
        // Create new auction
        auctions[auctionId] = AuctionLib.Auction({
            poolId: poolId,
            startTime: block.timestamp,
            duration: MAX_AUCTION_DURATION,
            isActive: true,
            isComplete: false,
            winner: address(0),
            winningBid: 0,
            totalBids: 0
        });
        
        activeAuctions[poolId] = auctionId;
        
        emit AuctionStarted(auctionId, poolId, block.timestamp, MAX_AUCTION_DURATION);
    }
    
    /**
     * @notice Submit auction result from AVS operators
     * @param auctionId The auction ID
     * @param winner The winning bidder
     * @param winningBid The winning bid amount
     */
    function submitAuctionResult(
        bytes32 auctionId,
        address winner,
        uint256 winningBid
    ) external onlyAuthorizedOperator onlyActiveAuction(auctionId) nonReentrant {
        AuctionLib.Auction storage auction = auctions[auctionId];
        
        // Validate auction timing
        require(
            block.timestamp >= auction.startTime + auction.duration,
            "EigenLVR: auction not ended"
        );
        
        // Update auction state
        auction.winner = winner;
        auction.winningBid = winningBid;
        auction.isComplete = true;
        auction.isActive = false;
        
        emit AuctionEnded(auctionId, auction.poolId, winner, winningBid);
    }
    
    /**
     * @notice Process auction result and distribute MEV
     * @param poolId The pool ID
     * @param auctionId The auction ID
     */
    function _processAuctionResult(PoolId poolId, bytes32 auctionId) internal {
        AuctionLib.Auction storage auction = auctions[auctionId];
        uint256 totalProceeds = auction.winningBid;
        
        if (totalProceeds > 0) {
            // Calculate distribution amounts
            uint256 lpAmount = (totalProceeds * LP_REWARD_PERCENTAGE) / BASIS_POINTS;
            uint256 avsAmount = (totalProceeds * AVS_REWARD_PERCENTAGE) / BASIS_POINTS;
            uint256 protocolAmount = (totalProceeds * PROTOCOL_FEE_PERCENTAGE) / BASIS_POINTS;
            
            // Distribute to LPs
            poolRewards[poolId] += lpAmount;
            _updateLPRewards(poolId, lpAmount);
            
            // Transfer to AVS operators and protocol
            if (avsAmount > 0) {
                payable(msg.sender).transfer(avsAmount);
            }
            if (protocolAmount > 0) {
                payable(feeRecipient).transfer(protocolAmount);
            }
            
            emit MEVDistributed(poolId, totalProceeds, lpAmount, avsAmount, protocolAmount);
        }
        
        // Clear active auction
        activeAuctions[poolId] = bytes32(0);
    }
    
    /**
     * @notice Update LP rewards based on their liquidity share
     * @param poolId The pool ID
     * @param rewardAmount The total reward amount for LPs
     */
    function _updateLPRewards(PoolId poolId, uint256 rewardAmount) internal {
        // This is a simplified implementation
        // In production, you'd need to iterate through LP positions
        // For now, we'll accumulate rewards that can be claimed proportionally
        poolRewards[poolId] += rewardAmount;
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIM FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Claim accumulated LP rewards
     * @param poolId The pool ID
     */
    function claimRewards(PoolId poolId) external nonReentrant {
        uint256 userLiquidity = lpLiquidity[poolId][msg.sender];
        require(userLiquidity > 0, "EigenLVR: no liquidity provided");
        
        uint256 totalPool = totalLiquidity[poolId];
        uint256 poolRewardBalance = poolRewards[poolId];
        
        // Calculate user's share of rewards
        uint256 userReward = (poolRewardBalance * userLiquidity) / totalPool;
        
        if (userReward > 0) {
            lpRewards[poolId][msg.sender] += userReward;
            poolRewards[poolId] -= userReward;
            
            payable(msg.sender).transfer(userReward);
            
            emit RewardsClaimed(poolId, msg.sender, userReward);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Authorize or deauthorize AVS operators
     * @param operator The operator address
     * @param authorized Whether to authorize the operator
     */
    function setOperatorAuthorization(address operator, bool authorized) external onlyOwner {
        authorizedOperators[operator] = authorized;
        emit OperatorAuthorized(operator, authorized);
    }
    
    /**
     * @notice Update LVR threshold for auction triggering
     * @param newThreshold The new threshold in basis points
     */
    function setLVRThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold <= 1000, "EigenLVR: threshold too high"); // Max 10%
        uint256 oldThreshold = lvrThreshold;
        lvrThreshold = newThreshold;
        emit LVRThresholdUpdated(oldThreshold, newThreshold);
    }
    
    /**
     * @notice Update fee recipient
     * @param newFeeRecipient The new fee recipient address
     */
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "EigenLVR: invalid address");
        feeRecipient = newFeeRecipient;
    }
    
    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Check if an auction should be triggered based on LVR
     * @param key The pool key
     * @param params The swap parameters
     * @return Whether to trigger an auction
     */
    function _shouldTriggerAuction(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) internal view returns (bool) {
        // Get current pool price and external price
        uint256 poolPrice = _getPoolPrice(key);
        uint256 externalPrice = priceOracle.getPrice(key.currency0, key.currency1);
        
        // Calculate price deviation
        uint256 deviation = poolPrice > externalPrice
            ? ((poolPrice - externalPrice) * BASIS_POINTS) / externalPrice
            : ((externalPrice - poolPrice) * BASIS_POINTS) / poolPrice;
        
        // Check if deviation exceeds threshold and swap size is significant
        return deviation >= lvrThreshold && _isSignificantSwap(params);
    }
    
    /**
     * @notice Get current pool price (simplified implementation)
     * @param key The pool key
     * @return The current pool price
     */
    function _getPoolPrice(PoolKey calldata key) internal view returns (uint256) {
        // This is a simplified implementation
        // In production, you'd calculate the actual pool price from sqrt price
        return 1e18; // Placeholder
    }
    
    /**
     * @notice Check if swap is significant enough to warrant auction
     * @param params The swap parameters
     * @return Whether the swap is significant
     */
    function _isSignificantSwap(IPoolManager.SwapParams calldata params) internal pure returns (bool) {
        // Consider swaps above 1 ETH equivalent as significant
        return params.amountSpecified > 1e18 || params.amountSpecified < -1e18;
    }
    
    /**
     * @notice Receive ETH for auction payments
     */
    receive() external payable {}
}