// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library UBI4ALLTypes {
    // Token constants
    uint256 constant TOTAL_SUPPLY = 99_000_000_000_000_000_000_000;
    uint256 constant TREASURY_ALLOCATION = 90; // 90%
    uint256 constant CONTRACT_ALLOCATION = 10; // 10%

    // UBI payment configuration
    struct UBIPayment {
        uint256 amount; // Monthly payment in EUR
        uint256 duration; // Duration in months
    }
}