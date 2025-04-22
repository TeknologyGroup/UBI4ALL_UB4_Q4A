// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/// @title IUBI4ALLOracle - Interfaccia per l'oracolo del prezzo EUR/USD
interface IUBI4ALLOracle {
    /// @notice Emesso quando il prezzo viene aggiornato
    event PriceUpdated(bytes32 indexed pair, uint256 price, uint256 timestamp);

    /// @notice Aggiorna manualmente il prezzo per una coppia
    function updatePrice(
        bytes32 pair,
        uint256 price,
        uint256 timestamp,
        uint256 confidence
    ) external;

    /// @notice Ottiene il prezzo più recente per una coppia
    function getPrice(bytes32 pair) external view returns (uint256 price, uint256 timestamp, bool isValid);

    /// @notice Ottiene il prezzo aggregato per una coppia
    function getAggregatedPrice(bytes32 pair) external view returns (uint256 weightedPrice, uint256 timestamp, bool isValid);

    /// @notice Ottiene il prezzo direttamente dal feed Chainlink
    function getSourcePrice(address source) external view returns (uint256 price, uint256 timestamp, bool isValid);

    /// @notice Aggiunge o aggiorna un feed Chainlink
    function addOracleSource(
        bytes32 pair,
        address source,
        uint256 weight,
        uint256 heartbeat,
        uint256 maxDeviation,
        uint256 minConfidence
    ) external;

    /// @notice Rimuove un feed Chainlink
    function removeOracleSource(bytes32 pair, address source) external;

    /// @notice Ottiene il prezzo più recente per la coppia EUR/USD
    /// @return Prezzo più recente come int256
    function getLatestPrice() external view returns (int256);
}

/// @title UBI4ALLOracle - Oracolo per il prezzo EUR/USD
/// @notice Fornisce prezzi aggiornati per la coppia EUR/USD, con fallback a Chainlink
contract UBI4ALLOracle is IUBI4ALLOracle, Ownable, ReentrancyGuard, Pausable {
    /// @dev Struttura per i dati del prezzo
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        bool isValid;
    }

    AggregatorV3Interface public priceFeed;
    bytes32 public constant EUR_USD_PAIR = bytes32("EUR/USD");
    mapping(bytes32 => PriceData) public latestPrices;
    uint256 public constant PRICE_VALIDITY_PERIOD = 15 minutes;
    uint256 public constant CHAINLINK_STALENESS_THRESHOLD = 1 hours;

    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);
    event EmergencyPause(bytes32 indexed pair);

    constructor(address _priceFeed, address initialOwner) Ownable(initialOwner) {
        require(_priceFeed != address(0), "Invalid price feed address");
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function getPrice(bytes32 pair) 
        public 
        view 
        override 
        returns (uint256 price, uint256 timestamp, bool isValid) 
    {
        require(pair == EUR_USD_PAIR, "Invalid pair");
        PriceData memory data = latestPrices[pair];

        if (data.isValid && block.timestamp - data.timestamp <= PRICE_VALIDITY_PERIOD) {
            return (data.price, data.timestamp, true);
        }

        try priceFeed.latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (answer <= 0) revert("Chainlink: Invalid price");
            if (updatedAt == 0) revert("Chainlink: Round not complete");
            if (block.timestamp - updatedAt > CHAINLINK_STALENESS_THRESHOLD) {
                revert("Chainlink: Stale price");
            }
            return (SafeCast.toUint256(answer), updatedAt, true);
        } catch {
            return (0, 0, false);
        }
    }

    function updatePrice(
        bytes32 pair,
        uint256 price,
        uint256 timestamp,
        uint256 /*confidence*/
    ) external override onlyOwner whenNotPaused nonReentrant {
        require(pair == EUR_USD_PAIR, "Invalid pair");
        require(timestamp <= block.timestamp, "Future timestamp");
        require(price > 0, "Invalid price");

        latestPrices[pair] = PriceData({
            price: price,
            timestamp: timestamp,
            isValid: true
        });

        emit PriceUpdated(pair, price, timestamp);
    }

    function getLatestPrice() external view override returns (int256) {
        (uint256 price, , bool isValid) = getPrice(EUR_USD_PAIR);
        require(isValid, "Invalid or stale price");
        return SafeCast.toInt256(price);
    }

    function getAggregatedPrice(bytes32 pair) 
        external 
        view 
        override 
        returns (uint256 weightedPrice, uint256 timestamp, bool isValid) 
    {
        return getPrice(pair);
    }

    function getSourcePrice(address source) 
        external 
        view 
        override 
        returns (uint256 price, uint256 timestamp, bool isValid) 
    {
        require(source == address(priceFeed), "Invalid source");
        try priceFeed.latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            if (answer <= 0) revert("Chainlink: Invalid price");
            if (updatedAt == 0) revert("Chainlink: Round not complete");
            if (block.timestamp - updatedAt > CHAINLINK_STALENESS_THRESHOLD) {
                revert("Chainlink: Stale price");
            }
            return (SafeCast.toUint256(answer), updatedAt, true);
        } catch {
            return (0, 0, false);
        }
    }

    function addOracleSource(
        bytes32 pair,
        address source,
        uint256 /*weight*/,
        uint256 /*heartbeat*/,
        uint256 /*maxDeviation*/,
        uint256 /*minConfidence*/
    ) external override onlyOwner nonReentrant {
        require(pair == EUR_USD_PAIR, "Invalid pair");
        require(source != address(0), "Invalid source address");

        address oldFeed = address(priceFeed);
        priceFeed = AggregatorV3Interface(source);
        emit PriceFeedUpdated(oldFeed, source);
    }

    function removeOracleSource(bytes32 pair, address source) external view override onlyOwner {
        require(pair == EUR_USD_PAIR, "Invalid pair");
        require(source == address(priceFeed), "Invalid source");
        // No-op: l'oracolo supporta una sola sorgente
    }

    function pause() external onlyOwner {
        _pause();
        emit EmergencyPause(EUR_USD_PAIR);
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}