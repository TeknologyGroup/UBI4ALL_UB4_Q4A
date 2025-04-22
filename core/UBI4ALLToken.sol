// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "../interfaces/IUBI4ALLToken.sol";
import "../interfaces/IUBI4ALLCustomOracle.sol";
import "../interfaces/IUBI4ALLQuantum.sol";

contract UBI4ALLToken is ERC20, Ownable, VRFConsumerBaseV2, IUBI4ALLToken, ERC20Votes, ERC20Permit {
    VRFCoordinatorV2Interface public COORDINATOR;

    // Costanti
    uint256 public constant TOTAL_SUPPLY = 10_000_000_000 * 10**18; // 10 miliardi di token
    uint256 public constant LOTTERY_FEE = 700; // 7%
    uint256 public constant BURN_FEE = 50; // 0.5%
    uint256 public constant FEE_DENOMINATOR = 10000; // Denominatore per le fee
    uint256 public constant LOTTERY_DURATION = 7 days; // Durata della lotteria
    uint256 public constant LOTTERY_AMOUNT = 100_000 * 10**18; // Premio lotteria

    // Variabili di stato
    address public treasuryWallet; // Wallet per le fee
    IUBI4ALLCustomOracle public oracle; // Oracolo per il prezzo Q4A
    IUBI4ALLQuantum public quantumToken; // Contratto Q4A
    bool public useQ4ARewards; // Abilita ricompense in Q4A
    bool public useSuperpositionRewards; // Abilita ricompense in superposizione
    address public financeContract; // Contratto finanziario
    address public governanceContract; // Contratto di governance
    mapping(uint8 => UBIPayment) public ubiPayments; // Pagamenti UBI per livello paese

    // Struttura per pagamenti UBI
    struct UBIPayment {
        uint256 amount; // Importo UBI
        uint256 duration; // Durata in secondi
        uint256 lastDistribution; // Ultima distribuzione
    }

    // Variabili lotteria
    uint256 public lotteryRound; // Round attuale
    uint256 public lotteryEndTime; // Timestamp di fine lotteria
    address[] public lotteryParticipants; // Partecipanti alla lotteria
    uint256 public requestId; // ID richiesta VRF
    uint64 public subscriptionId; // ID sottoscrizione Chainlink VRF
    bytes32 public keyHash; // Key hash per VRF
    uint32 public callbackGasLimit = 100000; // Gas limit per callback
    uint16 public requestConfirmations = 3; // Conferme richieste
    uint32 public numWords = 2; // Parole casuali: 1 per vincitore, 1 per proporzione

    // Eventi
    event LotteryStarted(uint256 indexed round, uint256 endTime);
    event LotteryEntered(address indexed participant, uint256 round);
    event LotteryWinner(address indexed winner, uint256 ub4Amount, uint256 q4aAmount, uint256 round);
    event Q4ARewardDistributed(address indexed winner, uint256 amount, uint256 round);
    event FeesBurned(uint256 amount);
    event UseQ4ARewardsToggled(bool enabled);
    event UseSuperpositionRewardsToggled(bool enabled);
    event QuantumTokenUpdated(address quantumToken);
    event FinanceContractUpdated(address financeContract);
    event GovernanceContractUpdated(address governanceContract);
    event UBIPaymentSet(uint8 countryLevel, uint256 amount, uint256 duration);

    // Costruttore
    constructor(
        address _treasuryWallet,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        address _oracle,
        address initialOwner
    )
        ERC20("UBI4ALL Token", "UB4")
        Ownable(initialOwner)
        VRFConsumerBaseV2(_vrfCoordinator)
        ERC20Permit("UBI4ALL Token")
    {
        require(_treasuryWallet != address(0), "Invalid treasury wallet");
        require(_oracle != address(0), "Invalid oracle address");
        require(_vrfCoordinator != address(0), "Invalid VRF coordinator");
        treasuryWallet = _treasuryWallet;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        oracle = IUBI4ALLCustomOracle(_oracle);
        _mint(address(this), TOTAL_SUPPLY);
    }

    // Override di balanceOf per risolvere il conflitto tra ERC20 e IUBI4ALLToken
    function balanceOf(address account) public view override(ERC20, IUBI4ALLToken) returns (uint256) {
        return super.balanceOf(account);
    }

    // Override di transfer per risolvere il conflitto tra ERC20 e IUBI4ALLToken
    function transfer(address to, uint256 value) public override(ERC20, IUBI4ALLToken) returns (bool) {
        return super.transfer(to, value);
    }

    // Imposta il contratto Q4A
    function setQuantumToken(address _quantumToken) external onlyOwner {
        require(_quantumToken != address(0), "Invalid quantum token address");
        quantumToken = IUBI4ALLQuantum(_quantumToken);
        emit QuantumTokenUpdated(_quantumToken);
    }

    // Attiva/disattiva ricompense in Q4A
    function toggleQ4ARewards(bool _enabled) external onlyOwner {
        useQ4ARewards = _enabled;
        emit UseQ4ARewardsToggled(_enabled);
    }

    // Attiva/disattiva ricompense in superposizione
    function toggleSuperpositionRewards(bool _enabled) external onlyOwner {
        useSuperpositionRewards = _enabled;
        emit UseSuperpositionRewardsToggled(_enabled);
    }

    // Inizia una nuova lotteria
    function startLottery() external onlyOwner {
        require(lotteryEndTime < block.timestamp || lotteryEndTime == 0, "Lottery already running");
        lotteryRound++;
        lotteryEndTime = block.timestamp + LOTTERY_DURATION;
        delete lotteryParticipants;
        emit LotteryStarted(lotteryRound, lotteryEndTime);
    }

    // Partecipa alla lotteria
    function enterLottery() external {
        require(lotteryEndTime > block.timestamp, "Lottery not running");
        require(balanceOf(msg.sender) >= 1 * 10**18, "Insufficient UB4 balance");
        _transfer(msg.sender, address(this), 1 * 10**18);
        lotteryParticipants.push(msg.sender);
        emit LotteryEntered(msg.sender, lotteryRound);
    }

    // Termina la lotteria e richiede numeri casuali
    function endLottery() external onlyOwner {
        require(lotteryEndTime <= block.timestamp, "Lottery not ended");
        require(lotteryParticipants.length > 0, "No participants");
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
    }

    // Gestisce i numeri casuali ricevuti da Chainlink VRF
    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override {
        uint256 winnerIndex = randomWords[0] % lotteryParticipants.length;
        address winner = lotteryParticipants[winnerIndex];
        uint256 ub4Amount = LOTTERY_AMOUNT;
        uint256 q4aAmount = 0;

        if (useSuperpositionRewards && address(quantumToken) != address(0)) {
            uint256 proportion = randomWords[1] % 101; // 0-100%
            ub4Amount = (LOTTERY_AMOUNT * proportion) / 100;
            q4aAmount = calculateQ4AAmount(LOTTERY_AMOUNT - ub4Amount);
            require(quantumToken.balanceOf(address(this)) >= q4aAmount, "Insufficient Q4A balance");
            quantumToken.transfer(winner, q4aAmount);
            emit Q4ARewardDistributed(winner, q4aAmount, lotteryRound);
        } else if (useQ4ARewards && address(quantumToken) != address(0)) {
            require(quantumToken.balanceOf(address(this)) >= LOTTERY_AMOUNT / 2, "Insufficient Q4A balance");
            ub4Amount = LOTTERY_AMOUNT / 2;
            q4aAmount = calculateQ4AAmount(ub4Amount);
            quantumToken.transfer(winner, q4aAmount);
            emit Q4ARewardDistributed(winner, q4aAmount, lotteryRound);
        }

        _transfer(address(this), winner, ub4Amount);
        emit LotteryWinner(winner, ub4Amount, q4aAmount, lotteryRound);
        lotteryEndTime = 0;
    }

    // Calcola l'importo in Q4A basato sui prezzi
    function calculateQ4AAmount(uint256 ub4Amount) internal view returns (uint256) {
        int256 q4aPrice = oracle.getQ4APrice();
        require(q4aPrice > 0, "Invalid Q4A price");
        uint256 ub4Price = 1 * 10**8; // Assume UB4 = 1 USD (8 decimali)
        return (ub4Amount * ub4Price) / uint256(q4aPrice);
    }

    // Override di _update per gestire fee e voti
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value); // Mint o burn
            return;
        }

        uint256 lotteryFee = (value * LOTTERY_FEE) / FEE_DENOMINATOR;
        uint256 burnFee = (value * BURN_FEE) / FEE_DENOMINATOR;
        uint256 amountAfterFees = value - lotteryFee - burnFee;

        super._update(from, address(0), burnFee); // Burn
        emit FeesBurned(burnFee);
        super._update(from, treasuryWallet, lotteryFee); // Fee al treasury
        super._update(from, to, amountAfterFees); // Trasferimento netto
    }

    // Implementazioni di IUBI4ALLToken
    function getTotalSupply() external view override returns (uint256) {
        return totalSupply();
    }

    function getTreasuryWallet() external view override returns (address) {
        return treasuryWallet;
    }

    function getLotteryPool() external view override returns (uint256) {
        return balanceOf(address(this));
    }

    function mint(address to, uint256 amount) external override onlyOwner {
        _mint(to, amount);
    }

    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
    }

    function emergencyRecoverTokens(address token, address to) external override onlyOwner {
        require(to != address(0), "Invalid recipient");
        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(to, amount);
    }

    function runLottery(uint8 countryLevel) external override onlyOwner returns (uint256) {
        require(lotteryEndTime <= block.timestamp, "Lottery not ended");
        require(lotteryParticipants.length > 0, "No participants");
        require(ubiPayments[countryLevel].amount > 0, "UBI payment not set");
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        return requestId;
    }

    function setFinanceContract(address financeContract_) external override onlyOwner {
        require(financeContract_ != address(0), "Invalid finance contract");
        financeContract = financeContract_;
        emit FinanceContractUpdated(financeContract_);
    }

    function setGovernanceContract(address governanceContract_) external override onlyOwner {
        require(governanceContract_ != address(0), "Invalid governance contract");
        governanceContract = governanceContract_;
        emit GovernanceContractUpdated(governanceContract_);
    }

    function setUBIPayment(uint8 countryLevel, uint256 amount, uint256 duration) external override onlyOwner {
        require(amount > 0, "Invalid UBI amount");
        require(duration > 0, "Invalid duration");
        ubiPayments[countryLevel] = UBIPayment(amount, duration, block.timestamp);
        emit UBIPaymentSet(countryLevel, amount, duration);
    }

    // Aggiorna parametri VRF
    function updateVRFParameters(
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyOwner {
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
    }

    // Funzioni di ERC20Votes
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}