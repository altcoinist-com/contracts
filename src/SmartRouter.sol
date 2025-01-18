// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/interfaces/IQuoterV2.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IPeripheryImmutableState} from "@uniswap/v3-periphery/interfaces/IPeripheryImmutableState.sol";

contract SmartRouter is Ownable {

    struct TradePath {
        bytes path;
        uint256 expectedAmount;
        uint160[] sqrtPriceX96AfterList;
        uint32[] initializedTicksCrossedList;
        uint256 gasEstimate;
    }

    uint256 internal constant EXACT_INPUT = 1;
    uint256 internal constant EXACT_OUTPUT = 2;

    uint256 internal constant NAME_MIN_SIZE = 3;
    uint256 internal constant NAME_MAX_SIZE = 72;

    uint256 internal constant DENOMINATOR = 1e4;


    IQuoterV2 public quoter;
    uint24[] private fees = [100, 500, 3000, 10000];
    address[] private sharedTokens;

    address public immutable factory;

    uint256 public constant version = 1;

    constructor(address _quoter, address[] memory _tokens) Ownable(msg.sender) {
        quoter = IQuoterV2(_quoter);
        sharedTokens = _tokens;
        factory = IPeripheryImmutableState(_quoter).factory();
    }

    function buildSinglePath(address token0, address token1, uint24 fee) public pure returns (bytes memory path) {
        path = abi.encodePacked(token0, fee, token1);
    }

    function buildMultiPath(address[] memory tokens, uint24[] memory _fees) public pure returns (bytes memory path) {
        uint256 length = tokens.length;
        require(length >= 2, "E: length error");
        path = abi.encodePacked(tokens[0], _fees[0], tokens[1]);

        for(uint256 i = 2; i < length; ++i) {
            path = abi.encodePacked(path, _fees[i - 1], tokens[i]);
        }
    }

    function exactInputPath(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external returns (TradePath memory path) {
        address[] memory tokens = sharedTokens;
        path = bestExactInputPath(tokenIn, tokenOut, amount, sharedTokens);
    }

    function exactOutputPath(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) external returns (TradePath memory path) {
        address[] memory tokens = sharedTokens;
        path = bestExactOutputPath(tokenIn, tokenOut, amount, tokens);
    }

    function bestExactInputPath(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address[] memory tokens
    ) public returns (TradePath memory path) {
        path = _bestV3Path(EXACT_INPUT, tokenIn, tokenOut, amountIn, tokens);
    }

    function bestExactOutputPath(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        address[] memory tokens
    ) public returns (TradePath memory path) {
        path = _bestV3Path(EXACT_OUTPUT, tokenOut, tokenIn, amountOut, tokens);
    }

    function bestExactInputPathWithFees(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address[] memory tokens,
        uint24[] memory v3Fees
    ) public returns (TradePath memory path) {
        path = _bestV3PathWithFees(EXACT_INPUT, tokenIn, tokenOut, amountIn, tokens, v3Fees);
    }


    function _bestV3PathWithFees(
        uint256 tradeType,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address[] memory tokens,
        uint24[] memory v3Fees
    ) internal returns (TradePath memory tradePath) {
        if (amount == 0 || tokenIn == address(0) || tokenOut == address(0) || tokenIn == tokenOut) return tradePath;

        if (v3Fees.length == 0) {
            v3Fees = fees;
        }
        uint256 feesLength = v3Fees.length;

        tradePath.expectedAmount = tradeType == EXACT_INPUT ? 0 : type(uint256).max;
        for (uint256 i = 0; i < feesLength; i++) {
            if(! checkV3PoolExist(tokenIn, tokenOut, v3Fees[i])) {
                continue;
            }
            bytes memory path = abi.encodePacked(tokenIn, v3Fees[i], tokenOut);
            (
                bool best,
                uint256 expectedAmount,
                uint160[] memory sqrtPriceX96AfterList,
                uint32[] memory initializedTicksCrossedList,
                uint256 gas
            ) = _getAmount(tradeType, path, amount, tradePath.expectedAmount);
            if (best) {
                tradePath.expectedAmount = expectedAmount;
                tradePath.sqrtPriceX96AfterList = sqrtPriceX96AfterList;
                tradePath.initializedTicksCrossedList = initializedTicksCrossedList;
                tradePath.gasEstimate = gas;
                tradePath.path = path;
            }
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenIn == tokens[i] || tokenOut == tokens[i]) continue;
            for (uint256 j = 0; j < feesLength; j++) {
                for (uint256 k = 0; k < feesLength; k++) {
                    if(! checkV3PoolExist(tokenIn, tokens[i], v3Fees[j])) {
                        continue;
                    }
                    if(! checkV3PoolExist(tokenOut, tokens[i], v3Fees[k])) {
                        continue;
                    }
                    bytes memory path = abi.encodePacked(tokenIn, v3Fees[j], tokens[i], v3Fees[k], tokenOut);
                    (
                        bool best,
                        uint256 expectedAmount,
                        uint160[] memory sqrtPriceX96AfterList,
                        uint32[] memory initializedTicksCrossedList,
                        uint256 gas
                    ) = _getAmount(tradeType, path, amount, tradePath.expectedAmount);
                    if (best) {
                        tradePath.expectedAmount = expectedAmount;
                        tradePath.sqrtPriceX96AfterList = sqrtPriceX96AfterList;
                        tradePath.initializedTicksCrossedList = initializedTicksCrossedList;
                        tradePath.gasEstimate = gas;
                        tradePath.path = path;
                    }
                }
            }
        }
    }

    function getFees() public view returns (uint24[] memory) {
        return fees;
    }

    function getSharedTokens() public view returns (address[] memory) {
        return sharedTokens;
    }

    function updateFees(uint24[] memory _fees) external onlyOwner {
        fees = _fees;
    }

    function updateTokens(address[] memory tokens) external onlyOwner {
        sharedTokens = tokens;
    }

    function _bestV3Path(
        uint256 tradeType,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        address[] memory tokens
    ) internal returns (TradePath memory tradePath) {
        if (amount == 0 || tokenIn == address(0) || tokenOut == address(0) || tokenIn == tokenOut) return tradePath;

        tradePath.expectedAmount = tradeType == EXACT_INPUT ? 0 : type(uint256).max;
        for (uint256 i = 0; i < fees.length; i++) {
            if(! checkV3PoolExist(tokenIn, tokenOut, fees[i])) {
                continue;
            }
            bytes memory path = abi.encodePacked(tokenIn, fees[i], tokenOut);
            (
                bool best,
                uint256 expectedAmount,
                uint160[] memory sqrtPriceX96AfterList,
                uint32[] memory initializedTicksCrossedList,
                uint256 gas
            ) = _getAmount(tradeType, path, amount, tradePath.expectedAmount);
            if (best) {
                tradePath.expectedAmount = expectedAmount;
                tradePath.sqrtPriceX96AfterList = sqrtPriceX96AfterList;
                tradePath.initializedTicksCrossedList = initializedTicksCrossedList;
                tradePath.gasEstimate = gas;
                tradePath.path = path;
            }
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenIn == tokens[i] || tokenOut == tokens[i]) continue;
            for (uint256 j = 0; j < fees.length; j++) {
                for (uint256 k = 0; k < fees.length; k++) {
                    if(! checkV3PoolExist(tokenIn, tokens[i], fees[j])) {
                        continue;
                    }
                    if(! checkV3PoolExist(tokenOut, tokens[i], fees[k])) {
                        continue;
                    }
                    bytes memory path = abi.encodePacked(tokenIn, fees[j], tokens[i], fees[k], tokenOut);
                    (
                        bool best,
                        uint256 expectedAmount,
                        uint160[] memory sqrtPriceX96AfterList,
                        uint32[] memory initializedTicksCrossedList,
                        uint256 gas
                    ) = _getAmount(tradeType, path, amount, tradePath.expectedAmount);
                    if (best) {
                        tradePath.expectedAmount = expectedAmount;
                        tradePath.sqrtPriceX96AfterList = sqrtPriceX96AfterList;
                        tradePath.initializedTicksCrossedList = initializedTicksCrossedList;
                        tradePath.gasEstimate = gas;
                        tradePath.path = path;
                    }
                }
            }
        }
    }

    function checkV3PoolExist(address token0, address token1, uint24 fee) private view returns (bool) {
        address pool = IUniswapV3Factory(factory).getPool(token0,token1, fee);
        return pool != address(0);
    }

    function _getAmount(
        uint256 tradeType,
        bytes memory path,
        uint256 amount,
        uint256 bestAmount
    )
        internal
        returns (
            bool best,
            uint256 expectedAmount,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        expectedAmount = bestAmount;
        if (tradeType == EXACT_INPUT) {
            try quoter.quoteExactInput(path, amount) returns (
                uint256 amountOut,
                uint160[] memory afterList,
                uint32[] memory crossedList,
                uint256 gas
            ) {
                expectedAmount = amountOut;
                sqrtPriceX96AfterList = afterList;
                initializedTicksCrossedList = crossedList;
                gasEstimate = gas;
            } catch {}
        } else if (tradeType == EXACT_OUTPUT) {
            try quoter.quoteExactOutput(path, amount) returns (
                uint256 amountIn,
                uint160[] memory afterList,
                uint32[] memory crossedList,
                uint256 gas
            ) {
                expectedAmount = amountIn;
                sqrtPriceX96AfterList = afterList;
                initializedTicksCrossedList = crossedList;
                gasEstimate = gas;
            } catch {}
        }

        best =
            (tradeType == EXACT_INPUT && expectedAmount > bestAmount) ||
            (tradeType == EXACT_OUTPUT && expectedAmount < bestAmount);
    }

    function getExactInAmountOut(
        bytes memory path,
        uint256 amount
    )
        public
        returns (
            uint256 expectedAmount,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        try quoter.quoteExactInput(path, amount) returns (
            uint256 amountOut,
            uint160[] memory afterList,
            uint32[] memory crossedList,
            uint256 gas
        ) {
            expectedAmount = amountOut;
            sqrtPriceX96AfterList = afterList;
            initializedTicksCrossedList = crossedList;
            gasEstimate = gas;
        } catch {}
     
    }


    function getExactInputSingleAmountOut(
        IQuoterV2.QuoteExactInputSingleParams memory params
    ) public returns (
        uint256 eAmount,
        uint160 eSqrtPriceX96After,
        uint32 eInitializedTicksCrossed,
        uint256 eGasEstimate
    ) {
        try quoter.quoteExactInputSingle(params) returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        ) {
            eAmount = amountOut;
            eSqrtPriceX96After = sqrtPriceX96After;
            eInitializedTicksCrossed = initializedTicksCrossed;
            eGasEstimate = gasEstimate;
        } catch {}
    }

}
