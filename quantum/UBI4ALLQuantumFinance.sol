// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "../interfaces/IUBI4ALLQuantum.sol";
import "../oracle/UBI4ALLOracle.sol";
import "../interfaces/IUBI4ALLQuantumFinance.sol";

/// @title UBI4ALLQuantumFinance - Contratto di staking e finanza per il token Q4A
/// @notice Gestisce lo staking di token Q4A con APY variabile basato su VRF Chainlink e volatilità dell'oracolo
contract UBI4ALLQuantumFinance is Ownable, VRFConsumerBaseV2, IUBI4ALLQuantumFinance {
    IUBI4ALLQuantum public immutable quantumToken;
    IUBI4ALLOracle public immutable oracle;
    VRFCoordinatorV2Interface public immutable COORDINATOR;

    /// @dev APY base (10%, in base 10000)
    uint256 public constant BASE_APY = 10_00;
    /// @dev APY per DAO (12%, in base 10000)
    uint256 public constant DAO_APY = 12_00;
    /// @dev Bonus massimo per volatilità (2%, in base 10000)
    uint256 public constant VOLATILITY_BONUS = 2_00;
    /// @dev APY minimo per staking standard (8%, in base 10000)
    uint256 public constant SUPERPOSITION_MIN = 8_00;
    /// @dev APY massimo per staking standard (14%, in base 10000)
    uint256 public constant SUPERPOSITION_MAX = 14_00;
    /// @dev APY minimo per staking DAO (10%, in base 10000)
    uint256 public constant DAO_SUPERPOSITION_MIN = 10_00;
    /// @dev APY massimo per staking DAO (16%, in base 10000)
    uint256 public constant DAO_SUPERPOSITION_MAX = 16_00;
    /// @dev Intervallo di aggiornamento APY (30 giorni)
    uint256 public constant UPDATE_INTERVAL = 30 days;

    /// @dev Struttura per lo stake di un utente
    struct Stake {
        uint256 amount; // Importo staked standard
        uint256 daoAmount; // Importo staked per DAO
        uint256 lastUpdate; // Timestamp dell'ultimo aggiornamento
        uint256 accumulatedReward; // Ricompense accumulate
        uint256 currentAPY; // APY corrente
    }

    /// @dev Mappatura degli stake per utente
    mapping(address => Stake) public stakes;
    /// @dev Totale dei token staked
    uint256 public totalValueLocked;
    /// @dev Mappatura delle richieste VRF per utente
    mapping(uint256 => address) public requestToUser;
    /// @dev Gas key per VRF
    bytes32 public immutable keyHash;
    /// @dev ID della sottoscrizione VRF
    uint64 public immutable subscriptionId;
    /// @dev Limite di gas per il callback VRF
    uint32 public callbackGasLimit = 100_000;
    /// @dev Numero di conferme richieste per VRF
    uint16 public requestConfirmations = 3;
    /// @dev Numero di parole casuali richieste
    uint32 public numWords = 1;

    /// @notice Evento emesso quando un utente stake token
    event Staked(address indexed user, uint256 amount, bool isDAO);
    /// @notice Evento emesso quando un utente preleva token
    event Withdrawn(address indexed user, uint256 amount);
    /// @notice Evento emesso quando un utente reclama ricompense
    event RewardClaimed(address indexed user, uint256 amount);
    /// @notice Evento emesso quando l'APY di un utente viene aggiornato
    event APYUpdated(address indexed user, uint256 newAPY);
    /// @notice Evento emesso quando viene richiesta una nuova APY casuale
    event RandomAPYRequested(address indexed user, uint256 requestId);

    /// @notice Costruttore del contratto
    /// @param _quantumToken Indirizzo del contratto Q4A
    /// @param _oracle Indirizzo dell'oracolo
    /// @param _vrfCoordinator Indirizzo del coordinatore VRF Chainlink
    /// @param _keyHash Gas key per VRF
    /// @param _subscriptionId ID della sottoscrizione VRF
    /// @param initialOwner Indirizzo del proprietario iniziale
    constructor(
        address _quantumToken,
        address _oracle,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        address initialOwner
    ) Ownable(initialOwner) VRFConsumerBaseV2(_vrfCoordinator) {
        require(_quantumToken != address(0), "Invalid token address");
        require(_oracle != address(0), "Invalid oracle address");
        require(_vrfCoordinator != address(0), "Invalid VRF coordinator address");
        quantumToken = IUBI4ALLQuantum(_quantumToken);
        oracle = IUBI4ALLOracle(_oracle);
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
    }

    /// @notice Effettua lo staking di token Q4A
    /// @param amount Quantità di token da stakare
    function stake(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        updateStake(msg.sender);
        stakes[msg.sender].amount += amount;
        totalValueLocked += amount;
        require(quantumToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        requestSuperpositionAPY(msg.sender);
        emit Staked(msg.sender, amount, false);
    }

    /// @notice Effettua lo staking di token Q4A per la DAO
    /// @param amount Quantità di token da stakare
    function stakeForDAO(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        updateStake(msg.sender);
        stakes[msg.sender].daoAmount += amount;
        totalValueLocked += amount;
        require(quantumToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        quantumToken.lockForDAO(amount);
        requestSuperpositionAPY(msg.sender);
        emit Staked(msg.sender, amount, true);
    }

    /// @notice Preleva token staked
    /// @param amount Quantità di token da prelevare
    function withdraw(uint256 amount) external {
        updateStake(msg.sender);
        require(stakes[msg.sender].amount >= amount, "Insufficient staked amount");
        stakes[msg.sender].amount -= amount;
        totalValueLocked -= amount;
        require(quantumToken.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Reclama le ricompense accumulate
    function claimReward() external {
        updateStake(msg.sender);
        uint256 reward = stakes[msg.sender].accumulatedReward;
        require(reward > 0, "No rewards to claim");
        stakes[msg.sender].accumulatedReward = 0;
        require(quantumToken.transfer(msg.sender, reward), "Transfer failed");
        emit RewardClaimed(msg.sender, reward);
    }

    /// @notice Richiede un nuovo APY casuale tramite VRF Chainlink
    /// @param user Indirizzo dell'utente
    function requestSuperpositionAPY(address user) internal {
        if (block.timestamp >= stakes[user].lastUpdate + UPDATE_INTERVAL) {
            uint256 requestId = COORDINATOR.requestRandomWords(
                keyHash,
                subscriptionId,
                requestConfirmations,
                callbackGasLimit,
                numWords
            );
            requestToUser[requestId] = user;
            emit RandomAPYRequested(user, requestId);
        }
    }

    /// @notice Callback VRF per aggiornare l'APY
    /// @param requestId ID della richiesta VRF
    /// @param randomWords Parole casuali generate
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address user = requestToUser[requestId];
        require(user != address(0), "Invalid request ID");
        uint256 randomValue = randomWords[0] % 100;
        uint256 apyRange = stakes[user].daoAmount > 0 ? DAO_SUPERPOSITION_MAX - DAO_SUPERPOSITION_MIN : SUPERPOSITION_MAX - SUPERPOSITION_MIN;
        uint256 newAPY = (randomValue * apyRange / 100) + (stakes[user].daoAmount > 0 ? DAO_SUPERPOSITION_MIN : SUPERPOSITION_MIN);
        stakes[user].currentAPY = newAPY;
        stakes[user].lastUpdate = block.timestamp;
        delete requestToUser[requestId];
        emit APYUpdated(user, newAPY);
    }

    /// @notice Aggiorna lo stake di un utente
    /// @param user Indirizzo dell'utente
    function updateStake(address user) internal {
        Stake storage userStake = stakes[user];
        if (userStake.amount > 0 || userStake.daoAmount > 0) {
            uint256 timeElapsed = block.timestamp - userStake.lastUpdate;
            uint256 baseReward = calculateReward(user, userStake.amount, userStake.currentAPY);
            uint256 daoReward = calculateReward(user, userStake.daoAmount, userStake.currentAPY);
            userStake.accumulatedReward += baseReward + daoReward;
            userStake.lastUpdate = block.timestamp;
        }
    }

    /// @notice Calcola le ricompense per un importo staked
    /// @param user Indirizzo dell'utente
    /// @param amount Importo staked
    /// @param apy APY corrente
    /// @return Ricompensa calcolata
    function calculateReward(address user, uint256 amount, uint256 apy) internal view returns (uint256) {
        if (amount == 0) return 0;
        uint256 volatilityBonus = predictVolatility();
        uint256 totalAPY = apy + volatilityBonus;
        Stake storage userStake = stakes[user];
        uint256 timeElapsed = block.timestamp - userStake.lastUpdate;
        return (amount * totalAPY * timeElapsed / 365 days) / 10_000;
    }

    /// @notice Predice la volatilità basata sull'oracolo
    /// @return Bonus di volatilità
    function predictVolatility() internal view returns (uint256) {
        int256 price = oracle.getLatestPrice();
        if (price <= 0) return 0;
        // Simulazione volatilità (EMA 7 giorni)
        return VOLATILITY_BONUS / 2;
    }

    /// @notice Ottiene il saldo staked di un utente
    /// @param user Indirizzo dell'utente
    /// @return Saldo staked totale (standard + DAO)
    function getStakedBalance(address user) external view returns (uint256) {
        return stakes[user].amount + stakes[user].daoAmount;
    }

    /// @notice Ottiene il totale dei token staked
    /// @return Totale dei token staked
    function getTotalValueLocked() external view returns (uint256) {
        return totalValueLocked;
    }

    /// @notice Calcola le ricompense totali per un utente
    /// @param user Indirizzo dell'utente
    /// @return Ricompense totali (accumulate + in attesa)
    function calculateReward(address user) external view returns (uint256) {
        Stake storage userStake = stakes[user];
        uint256 baseReward = calculateReward(user, userStake.amount, userStake.currentAPY);
        uint256 daoReward = calculateReward(user, userStake.daoAmount, userStake.currentAPY);
        return userStake.accumulatedReward + baseReward + daoReward;
    }

    /// @notice Aggiorna i parametri VRF
    /// @param _callbackGasLimit Nuovo limite di gas per il callback
    /// @param _requestConfirmations Nuovo numero di conferme
    function updateVRFParams(uint32 _callbackGasLimit, uint16 _requestConfirmations) external onlyOwner {
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
    }

    /// @notice Trasferisce la proprietà del contratto a un nuovo proprietario
    /// @param newOwner Indirizzo del nuovo proprietario
    function transferOwnership(address newOwner) public override(Ownable, IUBI4ALLQuantumFinance) onlyOwner {
        super.transferOwnership(newOwner);
    }
}