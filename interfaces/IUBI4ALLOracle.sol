// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUBI4ALLOracle {
    function updatePrice(
        bytes32 pair,
        uint256 price,
        uint256 timestamp,
        uint256 confidence
    ) external;

    function getPrice(bytes32 pair)
        external
        view
        returns (uint256 price, uint256 timestamp, bool isValid);

    function getAggregatedPrice(bytes32 pair)
        external
        view
        returns (uint256 weightedPrice, uint256 timestamp, bool isValid);

    function getSourcePrice(address source)
        external
        view
        returns (uint256 price, uint256 timestamp, bool isValid);

    function addOracleSource(
        bytes32 pair,
        address source,
        uint256 weight,
        uint256 heartbeat,
        uint256 maxDeviation,
        uint256 minConfidence
    ) external;

    function removeOracleSource(bytes32 pair, address source) external;
}