// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IUBI4ALLOracle.sol";
import "../libraries/UBI4ALLMath.sol";

/// @title UBI4ALLTrading - Contratto per il trading con leva di UB4
/// @notice Permette agli utenti di aprire, chiudere e liquidare posizioni con leva su EUR/USD
contract UBI4ALLTrading is ReentrancyGuard, Ownable {
    using UBI4ALLMath for uint256;

    // Struttura per le posizioni
    struct Position {
        address trader; // Indirizzo del trader
        uint256 collateral; // Collateral depositato (in UB4)
        uint256 size; // Dimensione della posizione (collateral * leverage)
        uint256 entryPrice; // Prezzo di ingresso (EUR/USD)
        uint256 leverage; // Leva utilizzata
        bool isLong; // True per posizione long, false per short
        uint256 timestamp; // Timestamp di apertura
        uint256 liquidationPrice; // Prezzo di liquidazione
    }

    // Mappature
    mapping(uint256 => Position) public positions; // ID posizione => Dettagli posizione
    mapping(address => uint256[]) public userPositions; // Trader => Lista ID posizioni

    // Parametri di trading
    uint256 public nextPositionId = 1; // ID della prossima posizione
    uint256 public minCollateral = 100 * 10**18; // 100 UB4
    uint256 public maxLeverage = 10; // 10x
    uint256 public liquidationThreshold = 8000; // 80% (8000/10000)
    uint256 public fundingRate = 10; // 0.1% (10/10000)
    uint256 public protocolFee = 50; // 0.5% (50/10000)

    // Contratti collegati
    IERC20 public ubi4allToken; // Token UB4
    IUBI4ALLOracle public oracle; // Oracolo per il prezzo EUR/USD

    // Eventi
    event PositionOpened(
        uint256 indexed positionId,
        address indexed trader,
        uint256 collateral,
        uint256 size,
        uint256 leverage,
        bool isLong
    );
    event PositionClosed(uint256 indexed positionId, int256 pnl);
    event PositionLiquidated(uint256 indexed positionId, address liquidator);

    /// @notice Costruttore del contratto
    /// @param _ubi4allToken Indirizzo del token UB4
    /// @param _oracle Indirizzo dell'oracolo
    /// @param initialOwner Indirizzo del proprietario iniziale
    constructor(address _ubi4allToken, address _oracle, address initialOwner) Ownable(initialOwner) {
        require(_ubi4allToken != address(0), "Invalid token address");
        require(_oracle != address(0), "Invalid oracle address");
        ubi4allToken = IERC20(_ubi4allToken);
        oracle = IUBI4ALLOracle(_oracle);
    }

    /// @notice Apre una posizione con leva
    /// @param collateral Importo del collateral in UB4
    /// @param leverage Livello di leva (1x a maxLeverage)
    /// @param isLong True per posizione long, false per short
    function openPosition(uint256 collateral, uint256 leverage, bool isLong) external nonReentrant {
        require(collateral >= minCollateral, "Insufficient collateral");
        require(leverage >= 1 && leverage <= maxLeverage, "Invalid leverage");

        // Trasferisci il collateral
        require(ubi4allToken.transferFrom(msg.sender, address(this), collateral), "Transfer failed");

        // Ottieni il prezzo attuale
        (uint256 entryPrice, , bool isValid) = oracle.getPrice(bytes32("EUR/USD"));
        require(isValid, "Invalid price");

        // Calcola size e liquidation price
        uint256 size = collateral * leverage;
        uint256 liquidationPrice = isLong
            ? entryPrice.mulDiv(liquidationThreshold, 10000 * leverage)
            : entryPrice.mulDiv(10000 + liquidationThreshold, 10000 * leverage);

        // Crea la posizione
        positions[nextPositionId] = Position({
            trader: msg.sender,
            collateral: collateral,
            size: size,
            entryPrice: entryPrice,
            leverage: leverage,
            isLong: isLong,
            timestamp: block.timestamp,
            liquidationPrice: liquidationPrice
        });

        userPositions[msg.sender].push(nextPositionId);
        emit PositionOpened(nextPositionId, msg.sender, collateral, size, leverage, isLong);
        nextPositionId++;
    }

    /// @notice Chiude una posizione e trasferisce i fondi
    /// @param positionId ID della posizione da chiudere
    function closePosition(uint256 positionId) external nonReentrant {
        Position storage position = positions[positionId];
        require(position.trader == msg.sender, "Not your position");
        require(position.collateral > 0, "Position does not exist");

        // Ottieni il prezzo attuale
        (uint256 currentPrice, , bool isValid) = oracle.getPrice(bytes32("EUR/USD"));
        require(isValid, "Invalid price");

        // Calcola PnL
        int256 pnl = calculatePnL(position, currentPrice);

        // Calcola l'importo da trasferire
        uint256 totalAmount;
        if (pnl >= 0) {
            totalAmount = position.collateral + uint256(pnl);
        } else {
            uint256 loss = uint256(-pnl);
            totalAmount = loss > position.collateral ? 0 : position.collateral - loss;
        }

        // Trasferisci fondi
        if (totalAmount > 0) {
            require(ubi4allToken.transfer(msg.sender, totalAmount), "Transfer failed");
        }

        emit PositionClosed(positionId, pnl);

        // Rimuovi la posizione
        delete positions[positionId];
        _removeUserPosition(msg.sender, positionId);
    }

    /// @notice Liquida una posizione se raggiunge il prezzo di liquidazione
    /// @param positionId ID della posizione da liquidare
    function liquidatePosition(uint256 positionId) external nonReentrant {
        Position storage position = positions[positionId];
        require(position.collateral > 0, "Position does not exist");

        // Ottieni il prezzo attuale
        (uint256 currentPrice, , bool isValid) = oracle.getPrice(bytes32("EUR/USD"));
        require(isValid, "Invalid price");

        // Verifica se la posizione è liquidabile
        require(
            (position.isLong && currentPrice <= position.liquidationPrice) ||
            (!position.isLong && currentPrice >= position.liquidationPrice),
            "Not liquidatable"
        );

        // Liquidatore riceve il 5% del collateral
        uint256 reward = position.collateral * 5 / 100;
        require(ubi4allToken.transfer(msg.sender, reward), "Transfer failed");

        emit PositionLiquidated(positionId, msg.sender);

        // Rimuovi la posizione
        delete positions[positionId];
        _removeUserPosition(position.trader, positionId);
    }

    /// @notice Calcola il profitto o la perdita (PnL) di una posizione
    /// @param position Dettagli della posizione
    /// @param currentPrice Prezzo attuale di EUR/USD
    /// @return pnl Profitto o perdita (può essere negativo)
    function calculatePnL(Position memory position, uint256 currentPrice) internal pure returns (int256) {
        require(position.entryPrice > 0, "Invalid entry price");
        if (position.isLong) {
            return
                (int256(position.size) * (int256(currentPrice) - int256(position.entryPrice))) /
                int256(position.entryPrice);
        } else {
            return
                (int256(position.size) * (int256(position.entryPrice) - int256(currentPrice))) /
                int256(position.entryPrice);
        }
    }

    /// @notice Imposta il collateral minimo
    /// @param _minCollateral Nuovo valore del collateral minimo
    function setMinCollateral(uint256 _minCollateral) external onlyOwner {
        require(_minCollateral > 0, "Invalid collateral");
        minCollateral = _minCollateral;
    }

    /// @notice Imposta la leva massima
    /// @param _maxLeverage Nuovo valore della leva massima
    function setMaxLeverage(uint256 _maxLeverage) external onlyOwner {
        require(_maxLeverage >= 1, "Invalid leverage");
        maxLeverage = _maxLeverage;
    }

    /// @notice Rimuove un ID posizione dalla lista dell'utente
    /// @param user Indirizzo dell'utente
    /// @param positionId ID della posizione da rimuovere
    function _removeUserPosition(address user, uint256 positionId) internal {
        uint256[] storage positionIds = userPositions[user];
        for (uint256 i = 0; i < positionIds.length; i++) {
            if (positionIds[i] == positionId) {
                positionIds[i] = positionIds[positionIds.length - 1];
                positionIds.pop();
                break;
            }
        }
    }
}