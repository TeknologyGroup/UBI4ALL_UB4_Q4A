// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUBI4ALLLiquidator {
    function addLiquidityUB4(uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin) external;
    function addLiquidityQ4A(uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin) external;
    function removeLiquidityUB4(uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin) external;
    function removeLiquidityQ4A(uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin) external;
    function swapQ4AtoUB4(uint256 amountIn, uint256 amountOutMin) external;
    function swapUB4toQ4A(uint256 amountIn, uint256 amountOutMin) external;
    function transferOwnership(address newOwner) external;
}