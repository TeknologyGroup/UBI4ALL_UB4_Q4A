// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title UBI4ALLTimelock - Contratto di timelock per la governance UBI4ALL
/// @notice Estende TimelockController per ritardare l'esecuzione delle proposte di governance
contract UBI4ALLTimelock is TimelockController {
    /// @notice Costruttore del contratto
    /// @param minDelay Ritardo minimo in secondi per l'esecuzione delle operazioni
    /// @param proposers Elenco degli indirizzi con ruolo PROPOSER_ROLE e CANCELLER_ROLE
    /// @param executors Elenco degli indirizzi con ruolo EXECUTOR_ROLE
    /// @param admin Indirizzo con ruolo DEFAULT_ADMIN_ROLE per configurazione iniziale (rinunciabile)
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}