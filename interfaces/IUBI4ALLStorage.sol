// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IUBI4ALLStorage
 * @dev Interface for the UBI4ALLStorage contract
 */
interface IUBI4ALLStorage {
    /**
     * @dev Save UBI4ALL data
     * @param data Data to be saved
     */
    function saveData(bytes32 data) external;

    /**
     * @dev Retrieve UBI4ALL data
     * @param data Data to retrieve
     * @return The stored data
     */
    function getData(bytes32 data) external view returns (bytes32);
}