// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IUBI4ALLToken.sol";
import "../interfaces/IUBI4ALLQuantum.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IUBI4ALLLiquidator.sol";

contract UBI4ALLLiquidator is IUBI4ALLLiquidator, Ownable {
    IERC20 public ubi4allToken;
    IERC20 public quantumToken;
    IUniswapV2Router02 public uniswapRouter;
    IUniswapV2Factory public uniswapFactory;
    address public liquidityWallet;

    uint256 public constant DEADLINE_EXTENSION = 20 minutes;

    event LiquidityAdded(address indexed token, uint256 amountToken, uint256 amountETH, uint256 liquidity);
    event LiquidityRemoved(address indexed token, uint256 amountToken, uint256 amountETH);
    event QuantumSwap(address indexed tokenIn, address indexed tokenOut, uint256 amount);

    constructor(
        address _ubi4allToken,
        address _quantumToken,
        address _uniswapRouter,
        address _uniswapFactory,
        address _liquidityWallet,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_ubi4allToken != address(0), "Invalid UB4 token address");
        require(_quantumToken != address(0), "Invalid Q4A token address");
        require(_uniswapRouter != address(0), "Invalid router address");
        require(_uniswapFactory != address(0), "Invalid factory address");
        require(_liquidityWallet != address(0), "Invalid liquidity wallet");
        ubi4allToken = IERC20(_ubi4allToken);
        quantumToken = IERC20(_quantumToken);
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        uniswapFactory = IUniswapV2Factory(_uniswapFactory);
        liquidityWallet = _liquidityWallet;
    }

    function addLiquidityUB4(
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin
    ) external onlyOwner {
        uint256 amount = amountTokenDesired;
        ubi4allToken.transferFrom(msg.sender, address(this), amount);
        ubi4allToken.approve(address(uniswapRouter), amount);

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = uniswapRouter.addLiquidityETH{value: address(this).balance}(
            address(ubi4allToken),
            amount,
            amountTokenMin,
            amountETHMin,
            liquidityWallet,
            block.timestamp + DEADLINE_EXTENSION
        );

        emit LiquidityAdded(address(ubi4allToken), amountToken, amountETH, liquidity);
    }

    function addLiquidityQ4A(
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin
    ) external onlyOwner {
        uint256 amount = amountTokenDesired;
        quantumToken.transferFrom(msg.sender, address(this), amount);
        quantumToken.approve(address(uniswapRouter), amount);

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = uniswapRouter.addLiquidityETH{value: address(this).balance}(
            address(quantumToken),
            amount,
            amountTokenMin,
            amountETHMin,
            liquidityWallet,
            block.timestamp + DEADLINE_EXTENSION
        );

        emit LiquidityAdded(address(quantumToken), amountToken, amountETH, liquidity);
    }

    function removeLiquidityUB4(
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin
    ) external onlyOwner {
        address pair = uniswapFactory.getPair(address(ubi4allToken), uniswapRouter.WETH());
        IERC20(pair).approve(address(uniswapRouter), liquidity);

        // Calcola il saldo del token prima della rimozione
        uint256 tokenBalanceBefore = ubi4allToken.balanceOf(liquidityWallet);

        uint256 amountETH = uniswapRouter.removeLiquidityETHSupportingFeeOnTransferTokens(
            address(ubi4allToken),
            liquidity,
            amountTokenMin,
            amountETHMin,
            liquidityWallet,
            block.timestamp + DEADLINE_EXTENSION
        );

        // Calcola il saldo del token dopo la rimozione
        uint256 tokenBalanceAfter = ubi4allToken.balanceOf(liquidityWallet);
        uint256 amountToken = tokenBalanceAfter - tokenBalanceBefore;

        emit LiquidityRemoved(address(ubi4allToken), amountToken, amountETH);
    }

    function removeLiquidityQ4A(
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin
    ) external onlyOwner {
        address pair = uniswapFactory.getPair(address(quantumToken), uniswapRouter.WETH());
        IERC20(pair).approve(address(uniswapRouter), liquidity);

        // Calcola il saldo del token prima della rimozione
        uint256 tokenBalanceBefore = quantumToken.balanceOf(liquidityWallet);

        uint256 amountETH = uniswapRouter.removeLiquidityETHSupportingFeeOnTransferTokens(
            address(quantumToken),
            liquidity,
            amountTokenMin,
            amountETHMin,
            liquidityWallet,
            block.timestamp + DEADLINE_EXTENSION
        );

        // Calcola il saldo del token dopo la rimozione
        uint256 tokenBalanceAfter = quantumToken.balanceOf(liquidityWallet);
        uint256 amountToken = tokenBalanceAfter - tokenBalanceBefore;

        emit LiquidityRemoved(address(quantumToken), amountToken, amountETH);
    }

    function swapQ4AtoUB4(uint256 amountIn, uint256 amountOutMin) external onlyOwner {
        quantumToken.transferFrom(msg.sender, address(this), amountIn);
        quantumToken.approve(address(uniswapRouter), amountIn);
        address[] memory path = new address[](2);
        path[0] = address(quantumToken);
        path[1] = address(ubi4allToken);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            liquidityWallet,
            block.timestamp + DEADLINE_EXTENSION
        );
        emit QuantumSwap(address(quantumToken), address(ubi4allToken), amountIn);
    }

    function swapUB4toQ4A(uint256 amountIn, uint256 amountOutMin) external onlyOwner {
        ubi4allToken.transferFrom(msg.sender, address(this), amountIn);
        ubi4allToken.approve(address(uniswapRouter), amountIn);
        address[] memory path = new address[](2);
        path[0] = address(ubi4allToken);
        path[1] = address(quantumToken);
        uniswapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            liquidityWallet,
            block.timestamp + DEADLINE_EXTENSION
        );
        emit QuantumSwap(address(ubi4allToken), address(quantumToken), amountIn);
    }

    function transferOwnership(address newOwner) public override(Ownable, IUBI4ALLLiquidator) onlyOwner {
        _transferOwnership(newOwner);
    }

    receive() external payable {}
}