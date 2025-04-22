// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library UBI4ALLMath {
    // Calcolo sicuro per a * b / c
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal pure returns (uint256) {
        return (a * b) / c;
    }

    // Calcolo della radice quadrata (per voto quadratico)
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

    // Calcolo del prezzo di liquidazione
    function calculateLiquidationPrice(
        uint256 entryPrice,
        uint256 leverage,
        uint256 threshold,
        bool isLong
    ) internal pure returns (uint256) {
        return isLong
            ? entryPrice - (entryPrice * threshold) / (leverage * 10000)
            : entryPrice + (entryPrice * threshold) / (leverage * 10000);
    }
}