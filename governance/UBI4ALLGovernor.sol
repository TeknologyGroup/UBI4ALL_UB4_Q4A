// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title UBI4ALLGovernor - Contratto di governance per UBI4ALL
/// @notice Gestisce proposte, voti quadratici e esecuzione tramite timelock
contract UBI4ALLGovernor is 
    Governor, 
    GovernorSettings, 
    GovernorVotes, 
    GovernorTimelockControl, 
    GovernorVotesQuorumFraction 
{
    /// @dev Mappatura dei voti per proposta e tipo di supporto (0=Against, 1=For, 2=Abstain)
    mapping(uint256 => mapping(uint8 => uint256)) private _proposalVotes; // proposalId => support => totalVotes

    /// @dev Evento emesso quando un voto viene registrato
    event VoteCounted(uint256 indexed proposalId, address voter, uint8 support, uint256 weight);

    /// @notice Costruttore del contratto
    /// @param _token Contratto del token di voto (UBI4ALLToken)
    /// @param _timelock Contratto TimelockController
    constructor(
        IVotes _token,
        TimelockController _timelock
    )
        Governor("UBI4ALLGovernor")
        GovernorSettings(
            1, // Voting delay: 1 block (~2 seconds on Polygon)
            45818, // Voting period: ~1 week (2s/block)
            1_000_000 * 10**18 // Proposal threshold: 1M UB4
        )
        GovernorVotes(_token)
        GovernorTimelockControl(_timelock)
        GovernorVotesQuorumFraction(5) // Quorum: 5%
    {}

    /// @notice Ritardo di voto
    /// @return Numero di blocchi prima dell'inizio del voto
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /// @notice Periodo di voto
    /// @return Durata del periodo di voto in blocchi
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /// @notice Soglia per creare una proposta
    /// @return Numero minimo di token necessari
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /// @notice Quorum necessario per una proposta
    /// @param blockNumber Blocco di riferimento
    /// @return Numero minimo di voti necessari
    function quorum(uint256 blockNumber) 
        public 
        view 
        override(Governor, GovernorVotesQuorumFraction) 
        returns (uint256) 
    {
        return super.quorum(blockNumber);
    }

    /// @notice Stato di una proposta
    /// @param proposalId ID della proposta
    /// @return Stato corrente (Pending, Active, etc.)
    function state(uint256 proposalId) 
        public 
        view 
        override(Governor, GovernorTimelockControl) 
        returns (ProposalState) 
    {
        return super.state(proposalId);
    }

    /// @notice Crea una nuova proposta
    /// @param targets Contratti da chiamare
    /// @param values Valori ETH da inviare
    /// @param calldatas Dati delle chiamate
    /// @param description Descrizione della proposta
    /// @return ID della proposta creata
    function propose(
        address[] memory targets, 
        uint256[] memory values, 
        bytes[] memory calldatas, 
        string memory description
    )
        public
        override(Governor)
        returns (uint256)
    {
        return super.propose(targets, values, calldatas, description);
    }

    /// @dev Esegue le operazioni di una proposta
    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
    {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Accoda le operazioni di una proposta al timelock
    /// @return Timestamp di esecuzione previsto
    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint48)
    {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    /// @dev Cancella una proposta
    /// @return ID della proposta cancellata
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /// @dev Indirizzo dell'esecutore (timelock)
    function _executor() 
        internal 
        view 
        override(Governor, GovernorTimelockControl) 
        returns (address) 
    {
        return super._executor();
    }

    /// @notice Verifica il supporto per un'interfaccia
    /// @param interfaceId ID dell'interfaccia
    /// @return True se l'interfaccia è supportata
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(Governor) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Verifica se una proposta richiede accodamento
    /// @param proposalId ID della proposta
    /// @return True se l'accodamento è necessario
    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    /// @notice Modalità di conteggio dei voti
    /// @return Stringa che descrive la modalità (bravo, quorum=for)
    function COUNTING_MODE() public pure override returns (string memory) {
        return "support=bravo&quorum=for";
    }

    /// @notice Verifica se un account ha già votato
    /// @param proposalId ID della proposta
    /// @param account Indirizzo dell'account
    /// @return True se l'account ha votato
    function hasVoted(uint256 proposalId, address account) public view override returns (bool) {
        return _hasVoted(proposalId, account);
    }

    /// @dev Registra un voto per una proposta
    /// @param proposalId ID della proposta
    /// @param account Indirizzo del votante
    /// @param support Tipo di voto (0=Against, 1=For, 2=Abstain)
    /// @param weight Peso del voto
    /// @param params Parametri aggiuntivi
    /// @return Peso del voto registrato
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory params
    ) internal override returns (uint256) {
        _proposalVotes[proposalId][support] += weight;
        emit VoteCounted(proposalId, account, support, weight);
        return weight;
    }

    /// @dev Verifica se il quorum è stato raggiunto
    /// @param proposalId ID della proposta
    /// @return True se il quorum è raggiunto
    function _quorumReached(uint256 proposalId) internal view override returns (bool) {
        uint256 forVotes = _getVotesForProposal(proposalId, 1);
        uint256 againstVotes = _getVotesForProposal(proposalId, 0);
        uint256 abstainVotes = _getVotesForProposal(proposalId, 2);
        return (forVotes + againstVotes + abstainVotes) >= quorum(proposalSnapshot(proposalId));
    }

    /// @dev Verifica se un account ha votato
    /// @param proposalId ID della proposta
    /// @param account Indirizzo dell'account
    /// @return True se l'account ha votato
    function _hasVoted(uint256 proposalId, address account) internal view returns (bool) {
        return _getVotes(account, proposalSnapshot(proposalId), "") > 0;
    }

    /// @dev Verifica se una proposta ha avuto successo
    /// @param proposalId ID della proposta
    /// @return True se i voti a favore superano quelli contrari
    function _voteSucceeded(uint256 proposalId) internal view override returns (bool) {
        uint256 forVotes = _getVotesForProposal(proposalId, 1);
        uint256 againstVotes = _getVotesForProposal(proposalId, 0);
        return forVotes > againstVotes;
    }

    /// @dev Ottiene i voti per un tipo di supporto
    /// @param proposalId ID della proposta
    /// @param support Tipo di voto (0=Against, 1=For, 2=Abstain)
    /// @return Totale dei voti per il tipo specificato
    function _getVotesForProposal(uint256 proposalId, uint8 support) internal view returns (uint256) {
        return _proposalVotes[proposalId][support];
    }

    /// @notice Vota con peso quadratico
    /// @param proposalId ID della proposta
    /// @param support Tipo di voto (0=Against, 1=For, 2=Abstain)
    /// @return Peso del voto registrato
    function castVoteWithQuadratic(uint256 proposalId, uint8 support) public returns (uint256) {
        address voter = msg.sender;
        uint256 weight = _getVotes(voter, proposalSnapshot(proposalId), "");
        weight = sqrt(weight); // Applica radice quadrata per voto quadratico
        bytes memory params = abi.encode(weight); // Codifica weight come params
        return _castVote(proposalId, voter, support, "", params);
    }

    /// @dev Calcola la radice quadrata per il voto quadratico
    /// @param x Valore di input
    /// @return Radice quadrata approssimata
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}