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
        uint256 price; // Prezzo della coppia (es. EUR/USD)
        uint256 timestamp; // Timestamp dell'aggiornamento
        bool isValid; // Validità del prezzo
    }

    /// @dev Feed di prezzo Chainlink
    AggregatorV3Interface public priceFeed;

    /// @dev Coppia supportata (EUR/USD)
    bytes32 public constant EUR_USD_PAIR = bytes32("EUR/USD");

    /// @dev Mappatura dei prezzi più recenti per coppia
    mapping(bytes32 => PriceData) public latestPrices;

    /// @dev Periodo di validità del prezzo (15 minuti)
    uint256 public constant PRICE_VALIDITY_PERIOD = 15 minutes;

    /// @dev Periodo massimo di validità per i dati di Chainlink (1 ora)
    uint256 public constant CHAINLINK_STALENESS_THRESHOLD = 1 hours;

    /// @notice Evento emesso quando il feed di prezzo viene aggiornato
    event PriceFeedUpdated(address indexed oldFeed, address indexed newFeed);

    /// @notice Evento emesso quando il contratto viene messo in pausa
    event EmergencyPause(bytes32 indexed pair);

    /// @notice Costruttore del contratto
    /// @param _priceFeed Indirizzo del feed Chainlink per EUR/USD
    /// @param initialOwner Indirizzo del proprietario iniziale
    constructor(address _priceFeed, address initialOwner) Ownable(initialOwner) {
        require(_priceFeed != address(0), "Invalid price feed address");
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Aggiorna manualmente il prezzo per la coppia EUR/USD
    /// @param pair Coppia di asset (deve essere EUR_USD_PAIR)
    /// @param price Prezzo da impostare
    /// @param timestamp Timestamp del prezzo
    /// @param confidence Livello di confidenza del prezzo (non utilizzato)
    function updatePrice(
        bytes32 pair,
        uint256 price,
        uint256 timestamp,
        uint256 confidence
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

    /// @notice Ottiene il prezzo più recente per la coppia EUR/USD
    /// @param pair Coppia di asset (deve essere EUR_USD_PAIR)
    /// @return price Prezzo della coppia
    /// @return timestamp Timestamp dell'aggiornamento
    /// @return isValid True se il prezzo è valido
    function getPrice(bytes32 pair) 
        external 
        view 
        override 
        returns (uint256 price, uint256 timestamp, bool isValid) 
    {
        require(pair == EUR_USD_PAIR, "Invalid pair");
        PriceData memory data = latestPrices[pair];

        if (data.isValid && block.timestamp - data.timestamp <= PRICE_VALIDITY_PERIOD) {
            return (data.price, data.timestamp, true);
        }

        // Fallback a Chainlink
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

    /// @notice Ottiene il prezzo più recente per la coppia EUR/USD
    /// @return Prezzo più recente come int256
    function getLatestPrice() external view override returns (int256) {
        (uint256 price, , bool isValid) = getPrice(EUR_USD_PAIR);
        require(isValid, "Invalid or stale price");
        return SafeCast.toInt256(price);
    }

    /// @notice Ottiene il prezzo aggregato (equivalente a getPrice per EUR/USD)
    /// @param pair Coppia di asset (deve essere EUR_USD_PAIR)
    /// @return weightedPrice Prezzo aggregato
    /// @return timestamp Timestamp dell'aggiornamento
    /// @return isValid True se il prezzo è valido
    function getAggregatedPrice(bytes32 pair) 
        external 
        view 
        override 
        returns (uint256 weightedPrice, uint256 timestamp, bool isValid) 
    {
        return getPrice(pair);
    }

    /// @notice Ottiene il prezzo direttamente dal feed Chainlink
    /// @param source Indirizzo del feed (deve corrispondere a priceFeed)
    /// @return price Prezzo della coppia
    /// @return timestamp Timestamp dell'aggiornamento
    /// @return isValid True se il prezzo è valido
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

    /// @notice Aggiunge o aggiorna il feed Chainlink per EUR/USD
    /// @param pair Coppia di asset (deve essere EUR_USD_PAIR)
    /// @param source Nuovo indirizzo del feed Chainlink
    /// @param weight Peso della sorgente (non utilizzato)
    /// @param heartbeat Frequenza di aggiornamento della sorgente (non utilizzato)
    /// @param maxDeviation Deviazione massima consentita (non utilizzato)
    /// @param minConfidence Confidenza minima richiesta (non utilizzato)
    function addOracleSource(
        bytes32 pair,
        address source,
        uint256 weight,
        uint256 heartbeat,
        uint256 maxDeviation,
        uint256 minConfidence
    ) external override onlyOwner nonReentrant {
        require(pair == EUR_USD_PAIR, "Invalid pair");
        require(source != address(0), "Invalid source address");

        address oldFeed = address(priceFeed);
        priceFeed = AggregatorV3Interface(source);
        emit PriceFeedUpdated(oldFeed, source);
    }

    /// @notice Rimuove un feed (no-op per oracolo a sorgente singola)
    /// @param pair Coppia di asset (deve essere EUR_USD_PAIR)
    /// @param source Indirizzo del feed da rimuovere
    function removeOracleSource(bytes32 pair, address source) external view override onlyOwner {
        require(pair == EUR_USD_PAIR, "Invalid pair");
        require(source == address(priceFeed), "Invalid source");
        // No-op: l'oracolo supporta una sola sorgente
    }

    /// @notice Mette in pausa il contratto (blocca updatePrice)
    function pause() external onlyOwner {
        _pause();
        emit EmergencyPause(EUR_USD_PAIR);
    }

    /// @notice Ripristina il contratto dalla pausa
    function unpause() external onlyOwner {
        _unpause();
    }
}