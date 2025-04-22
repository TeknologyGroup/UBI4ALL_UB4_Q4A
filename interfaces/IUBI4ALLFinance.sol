// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUBI4ALLFinance {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimReward() external;
    function requestLoan(uint256 amount, uint256 duration, uint256 collateral) external;
    function repayLoan(uint256 loanId) external;
    function getStakedBalance(address user) external view returns (uint256);
    function getTotalValueLocked() external view returns (uint256);
    function getTotalLoaned() external view returns (uint256);
    function transferOwnership(address newOwner) external;
}