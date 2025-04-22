// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUBI4ALLQuantum {
    event QuantumTransfer(address indexed from, address indexed to, uint256 amount);
    event TokensLockedForDAO(address indexed account, uint256 amount);
    event TokensUnlockedForDAO(address indexed account, uint256 amount);
    event TokensBurned(address indexed account, uint256 amount);
    event EmergencyRecovery(address indexed token, address indexed to, uint256 amount);
    event WalletUpdated(string walletType, address indexed newWallet);
    event VestingReleased(address indexed wallet, uint256 amount);
    event LeveragedTransfer(address indexed from, address indexed to, uint256 amount, uint256 leverage);

    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function getTotalSupply() external pure returns (uint256);
    function getAllocations() external pure returns (
        uint256 treasury,
        uint256 ecosystem,
        uint256 community,
        uint256 liquidity,
        uint256 reserve
    );
    function getWallets() external view returns (
        address treasury,
        address ecosystem,
        address community,
        address liquidity,
        address reserve
    );
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function emergencyRecoverTokens(address token, address to) external;
    function lockForDAO(uint256 amount) external;
    function lockedForDAO(address account) external view returns (uint256);
    function totalLockedForDAO() external view returns (uint256);
}