// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract UniswapV2TradeManager {
    IUniswapV2Router02 public immutable router;
    address public immutable WETH;
    address public immutable virtuals;

    constructor(address _router, address _virtuals) {
        router = IUniswapV2Router02(_router);
        WETH = router.WETH();
        virtuals = _virtuals;
    }

    function purchaseAsset(
        address tokenA,
        uint256 amountOutMin,
        uint256 deadline
    ) external payable {
        require(block.timestamp <= deadline, "TX EXPIRED");
        require(tokenA != virtuals && tokenA != WETH, "INVALID_TOKEN");

        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());

        // Check intermediate pools exist
        address pool1 = factory.getPair(WETH, virtuals);
        address pool2 = factory.getPair(virtuals, tokenA);
        require(pool1 != address(0) && pool2 != address(0), "POOL_NOT_FOUND");

        // Verify both pools have liquidity
        (uint112 reserveWETH, uint112 reserveVirtuals,) = IUniswapV2Pair(pool1).getReserves();
        (uint112 reserveVirtuals2, uint112 reserveTokenA,) = IUniswapV2Pair(pool2).getReserves();
        require(
            reserveWETH > 0 &&
            reserveVirtuals > 0 &&
            reserveVirtuals2 > 0 &&
            reserveTokenA > 0,
            "NO_LIQUIDITY"
        );

        // Create 3-hop path: WETH -> virtuals -> tokenA
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = virtuals;
        path[2] = tokenA;

        // Get expected output amount
        uint[] memory amounts = router.getAmountsOut(msg.value, path);
        require(amounts[2] >= amountOutMin, "INSUFFICIENT_OUTPUT");

        // Execute swap
        router.swapExactETHForTokens{value: msg.value}(
            amountOutMin,
            path,
            msg.sender,
            deadline
        );
    }

    receive() external payable {}
}
