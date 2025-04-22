// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUBI4ALLToken {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function getTotalSupply() external view returns (uint256);
    function getTreasuryWallet() external view returns (address);
    function getLotteryPool() external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function emergencyRecoverTokens(address token, address to) external;
    function runLottery(uint8 countryLevel) external returns (uint256);
    function setFinanceContract(address financeContract) external;
    function setGovernanceContract(address governanceContract) external;
    function setUBIPayment(uint8 countryLevel, uint256 amount, uint256 duration) external;
}