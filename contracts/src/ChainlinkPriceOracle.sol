// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ChainlinkPriceOracle
 * @notice Chainlink-based price oracle for LVR detection
 */
contract ChainlinkPriceOracle is IPriceOracle, Ownable {
    using CurrencyLibrary for Currency;

    /*//////////////////////////////////////////////////////////////
                                INTERFACES
    //////////////////////////////////////////////////////////////*/
    
    interface AggregatorV3Interface {
        function decimals() external view returns (uint8);
        function description() external view returns (string memory);
        function version() external view returns (uint256);
        function getRoundData(uint80 _roundId)
            external
            view
            returns (
                uint80 roundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            );
        function latestRoundData()
            external
            view
            returns (
                uint80 roundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            );
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Mapping of token pair to Chainlink price feed
    mapping(bytes32 => AggregatorV3Interface) public priceFeeds;
    
    /// @notice Maximum acceptable price staleness (1 hour)
    uint256 public constant MAX_PRICE_STALENESS = 1 hours;
    
    /// @notice Price precision (18 decimals)
    uint256 public constant PRICE_PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PriceFeedAdded(
        Currency indexed token0,
        Currency indexed token1,
        address indexed priceFeed
    );
    
    event PriceFeedRemoved(
        Currency indexed token0,
        Currency indexed token1
    );

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor() Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add a price feed for a token pair
     * @param token0 The first token
     * @param token1 The second token
     * @param priceFeed The Chainlink price feed address
     */
    function addPriceFeed(
        Currency token0,
        Currency token1,
        address priceFeed
    ) external onlyOwner {
        bytes32 pairKey = _getPairKey(token0, token1);
        priceFeeds[pairKey] = AggregatorV3Interface(priceFeed);
        emit PriceFeedAdded(token0, token1, priceFeed);
    }
    
    /**
     * @notice Remove a price feed for a token pair
     * @param token0 The first token
     * @param token1 The second token
     */
    function removePriceFeed(Currency token0, Currency token1) external onlyOwner {
        bytes32 pairKey = _getPairKey(token0, token1);
        delete priceFeeds[pairKey];
        emit PriceFeedRemoved(token0, token1);
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getPrice(Currency token0, Currency token1) external view override returns (uint256 price) {
        bytes32 pairKey = _getPairKey(token0, token1);
        AggregatorV3Interface priceFeed = priceFeeds[pairKey];
        
        require(address(priceFeed) != address(0), "ChainlinkOracle: no price feed");
        
        (, int256 answer, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        
        require(answer > 0, "ChainlinkOracle: invalid price");
        require(
            block.timestamp - updatedAt <= MAX_PRICE_STALENESS,
            "ChainlinkOracle: stale price"
        );
        
        uint8 decimals = priceFeed.decimals();
        price = _normalizePrice(uint256(answer), decimals);
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getPriceAtTime(
        Currency token0,
        Currency token1,
        uint256 timestamp
    ) external view override returns (uint256 price) {
        // For simplicity, return current price
        // In production, you'd implement historical price lookup
        return this.getPrice(token0, token1);
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function isPriceStale(Currency token0, Currency token1) external view override returns (bool isStale) {
        bytes32 pairKey = _getPairKey(token0, token1);
        AggregatorV3Interface priceFeed = priceFeeds[pairKey];
        
        if (address(priceFeed) == address(0)) return true;
        
        (, , , uint256 updatedAt, ) = priceFeed.latestRoundData();
        isStale = block.timestamp - updatedAt > MAX_PRICE_STALENESS;
    }
    
    /**
     * @inheritdoc IPriceOracle
     */
    function getLastUpdateTime(Currency token0, Currency token1) external view override returns (uint256 timestamp) {
        bytes32 pairKey = _getPairKey(token0, token1);
        AggregatorV3Interface priceFeed = priceFeeds[pairKey];
        
        require(address(priceFeed) != address(0), "ChainlinkOracle: no price feed");
        
        (, , , uint256 updatedAt, ) = priceFeed.latestRoundData();
        timestamp = updatedAt;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Generate a unique key for a token pair
     * @param token0 The first token
     * @param token1 The second token
     * @return The pair key
     */
    function _getPairKey(Currency token0, Currency token1) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token0, token1));
    }
    
    /**
     * @notice Normalize price to 18 decimals
     * @param price The raw price from Chainlink
     * @param decimals The price feed decimals
     * @return The normalized price
     */
    function _normalizePrice(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals < 18) {
            return price * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return price / (10 ** (decimals - 18));
        }
        return price;
    }
}