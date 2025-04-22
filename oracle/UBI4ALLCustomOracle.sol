// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import "../interfaces/IUBI4ALLCustomOracle.sol";

contract UBI4ALLCustomOracle is IUBI4ALLCustomOracle, Ownable, FunctionsClient {
    using FunctionsRequest for FunctionsRequest.Request;

    // Costanti
    uint8 public constant DECIMALS = 8; // Decimali per il prezzo Q4A (come Chainlink Price Feed)
    uint256 public constant REPUTATION_SCALE = 100; // Scala per i punteggi di reputazione (0-100)
    uint256 public constant CORRELATION_SCALE = 100; // Scala per i punteggi di correlazione (0-100)

    // Variabili di stato
    mapping(address => uint256) public reputationScores; // Punteggi di reputazione per utente
    mapping(address => mapping(uint256 => uint256)) public correlationScores; // Punteggi di correlazione per utente e proposta
    int256 public q4aPrice; // Prezzo attuale di Q4A (in USD, 8 decimali)
    uint256 public lastPriceUpdate; // Timestamp dell'ultimo aggiornamento del prezzo
    mapping(bytes32 => RequestData) public pendingRequests; // Traccia delle richieste in sospeso

    // Struttura per tracciare le richieste
    struct RequestData {
        address requester;
        RequestType requestType;
        address user;
        uint256 proposalId;
    }

    // Tipi di richiesta
    enum RequestType { Q4APrice, ReputationScore, CorrelationScore }

    // Parametri Chainlink Functions
    bytes32 public donID; // ID del DON per Chainlink Functions
    uint64 public subscriptionId; // ID della sottoscrizione Chainlink Functions
    uint32 public gasLimit = 300000; // Limite di gas per le callback

    // Eventi
    event Q4APriceUpdated(int256 price, uint256 timestamp);
    event ReputationScoreUpdated(address indexed user, uint256 score);
    event CorrelationScoreUpdated(address indexed user, uint256 indexed proposalId, uint256 score);
    event OracleRequest(bytes32 indexed requestId, address indexed requester, RequestType requestType);
    event OracleResponse(bytes32 indexed requestId, int256 price, uint256 reputation, uint256 correlation);

    // Costruttore
    constructor(
        address _functionsRouter,
        bytes32 _donID,
        uint64 _subscriptionId,
        address initialOwner
    ) Ownable(initialOwner) FunctionsClient(_functionsRouter) {
        require(_functionsRouter != address(0), "Invalid router address");
        donID = _donID;
        subscriptionId = _subscriptionId;
        q4aPrice = int256(1 * 10**DECIMALS); // Prezzo iniziale: 1 USD
        lastPriceUpdate = block.timestamp;
    }

    // Richiesta del prezzo Q4A tramite Chainlink Functions
    function requestQ4APrice() external onlyOwner returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(getPriceScript());
        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
        pendingRequests[requestId] = RequestData(msg.sender, RequestType.Q4APrice, address(0), 0);
        emit OracleRequest(requestId, msg.sender, RequestType.Q4APrice);
        return requestId;
    }

    // Richiesta del punteggio di reputazione per un utente
    function requestReputationScore(address _user) external onlyOwner returns (bytes32 requestId) {
        require(_user != address(0), "Invalid user address");
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(getReputationScript(_user));
        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
        pendingRequests[requestId] = RequestData(msg.sender, RequestType.ReputationScore, _user, 0);
        emit OracleRequest(requestId, msg.sender, RequestType.ReputationScore);
        return requestId;
    }

    // Richiesta del punteggio di correlazione per un utente e una proposta
    function requestCorrelationScore(address _user, uint256 _proposalId) external onlyOwner returns (bytes32 requestId) {
        require(_user != address(0), "Invalid user address");
        require(_proposalId > 0, "Invalid proposal ID");
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(getCorrelationScript(_user, _proposalId));
        requestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donID);
        pendingRequests[requestId] = RequestData(msg.sender, RequestType.CorrelationScore, _user, _proposalId);
        emit OracleRequest(requestId, msg.sender, RequestType.CorrelationScore);
        return requestId;
    }

    // Gestione della risposta di Chainlink Functions
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory) internal override {
        RequestData memory request = pendingRequests[requestId];
        require(request.requester != address(0), "Invalid request ID");

        (int256 price, uint256 reputation, uint256 correlation) = abi.decode(response, (int256, uint256, uint256));

        if (request.requestType == RequestType.Q4APrice && price > 0) {
            q4aPrice = price;
            lastPriceUpdate = block.timestamp;
            emit Q4APriceUpdated(price, block.timestamp);
        } else if (request.requestType == RequestType.ReputationScore && reputation <= REPUTATION_SCALE) {
            reputationScores[request.user] = reputation;
            emit ReputationScoreUpdated(request.user, reputation);
        } else if (request.requestType == RequestType.CorrelationScore && correlation <= CORRELATION_SCALE) {
            correlationScores[request.user][request.proposalId] = correlation;
            emit CorrelationScoreUpdated(request.user, request.proposalId, correlation);
        }

        emit OracleResponse(requestId, price, reputation, correlation);
        delete pendingRequests[requestId];
    }

    // Aggiornamento manuale del prezzo Q4A (per test o fallback)
    function updateManualQ4APrice(int256 _price) external onlyOwner {
        require(_price > 0, "Invalid price");
        q4aPrice = _price;
        lastPriceUpdate = block.timestamp;
        emit Q4APriceUpdated(_price, block.timestamp);
    }

    // Aggiornamento manuale del punteggio di reputazione (per test o fallback)
    function updateManualReputationScore(address _user, uint256 _score) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_score <= REPUTATION_SCALE, "Invalid reputation score");
        reputationScores[_user] = _score;
        emit ReputationScoreUpdated(_user, _score);
    }

    // Aggiornamento manuale del punteggio di correlazione (per test o fallback)
    function updateManualCorrelationScore(address _user, uint256 _proposalId, uint256 _score) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_proposalId > 0, "Invalid proposal ID");
        require(_score <= CORRELATION_SCALE, "Invalid correlation score");
        correlationScores[_user][_proposalId] = _score;
        emit CorrelationScoreUpdated(_user, _proposalId, _score);
    }

    // Getter per il prezzo Q4A
    function getQ4APrice() external view override returns (int256) {
        return q4aPrice;
    }

    // Getter per il punteggio di reputazione
    function getReputationScore(address _user) external view override returns (uint256) {
        return reputationScores[_user];
    }

    // Getter per il punteggio di correlazione
    function getCorrelationScore(address _user, uint256 _proposalId) external view override returns (uint256) {
        return correlationScores[_user][_proposalId];
    }

    // Script JavaScript per il prezzo Q4A (esempio)
    function getPriceScript() internal pure returns (string memory) {
        return
            "const apiResponse = await Functions.makeHttpRequest({"
            "url: 'https://api.quickswap.exchange/v1/price',"
            "params: { token: 'Q4A', base: 'USD' }"
            "});"
            "if (apiResponse.error) { throw Error('API Error'); }"
            "const price = Math.round(apiResponse.data.price * 10**8);"
            "return Functions.encodeInt256(price);";
    }

    // Script JavaScript per il punteggio di reputazione (esempio)
    function getReputationScript(address _user) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "const user = '", toHexString(_user), "';",
                "const apiResponse = await Functions.makeHttpRequest({"
                "url: 'https://ubi4all-dao-api.com/reputation',"
                "params: { user: user }"
                "});"
                "if (apiResponse.error) { throw Error('API Error'); }"
                "const score = Math.min(apiResponse.data.score, 100);"
                "return Functions.encodeUint256(score);"
            )
        );
    }

    // Script JavaScript per il punteggio di correlazione (esempio)
    function getCorrelationScript(address _user, uint256 _proposalId) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "const user = '", toHexString(_user), "';",
                "const proposalId = '", uint256ToString(_proposalId), "';",
                "const apiResponse = await Functions.makeHttpRequest({"
                "url: 'https://ubi4all-dao-api.com/correlation',"
                "params: { user: user, proposalId: proposalId }"
                "});"
                "if (apiResponse.error) { throw Error('API Error'); }"
                "const score = Math.min(apiResponse.data.score, 100);"
                "return Functions.encodeUint256(score);"
            )
        );
    }

    // Funzioni di utilità
    function toHexString(address addr) internal pure returns (string memory) {
        bytes memory addrBytes = abi.encodePacked(addr);
        // Definiamo i caratteri esadecimali come un array fisso
        bytes1[16] memory hexChars = [
            bytes1("0"), bytes1("1"), bytes1("2"), bytes1("3"),
            bytes1("4"), bytes1("5"), bytes1("6"), bytes1("7"),
            bytes1("8"), bytes1("9"), bytes1("a"), bytes1("b"),
            bytes1("c"), bytes1("d"), bytes1("e"), bytes1("f")
        ];
        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            result[2 + i * 2] = hexChars[uint8(addrBytes[i] >> 4)];
            result[3 + i * 2] = hexChars[uint8(addrBytes[i] & 0x0f)];
        }
        return string(result);
    }

    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}