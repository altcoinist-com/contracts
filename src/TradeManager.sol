// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract TradeManager is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    struct CreatePositionParams {
        bytes path;
        uint256 amount;
        uint256 quote; // quote is offchain, and excludes fees
        uint256 slippage;
        address trenchOwner;
        address[] refs;
    }

    IV3SwapRouter public immutable swapRouter;
    IWETH public immutable weth;
    address public team;
    uint256 public minBuy;
    mapping (uint8 => uint256) fees;

    bool lockSwap;

    constructor(
        address _owner,
        address _team,
        address _router,
        address _weth
    ) Ownable(_owner) {
        swapRouter = IV3SwapRouter(_router);
        weth = IWETH(_weth);
        minBuy = 0.1 ether;
        team = _team;
        fees[0] = 100; // 1% base fee
        fees[1] = 20;
        fees[2] = 80;
        fees[3] = 10;
        fees[4] = 6;
        fees[5] = 3;
        fees[6] = 1;
    }

    function createPosition(
        CreatePositionParams calldata params
    ) external payable returns (uint256) {


        address tokenIn = address(bytes20(params.path[0:20]));
        require(tokenIn == address(weth), "WETHIN");
        require(params.amount >= minBuy, "MIN");
        require(msg.value >= params.amount, "VAL");
        weth.deposit{value: params.amount}();

        uint256 amountMinusFees = distributeFees(
            params.amount,
            params.trenchOwner,
            params.refs
        );

        uint256 amountOut = swap(params.path, amountMinusFees, params.quote, params.slippage, msg.sender);
        require(amountOut > 0, "SWAP");
        return amountOut;
    }

    function closePosition(
        CreatePositionParams calldata params
    ) external returns (uint256) {
        address tokenIn = address(bytes20(params.path[0:20]));
        address tokenOut = address(bytes20(params.path[params.path.length-20:]));

        require(tokenOut == address(weth), "WETHOUT");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), params.amount);

        uint256 amountOut = swap(params.path, params.amount, params.quote, params.slippage, address(this));

        uint256 amountMinusFees = distributeFees(
            amountOut,
            params.trenchOwner,
            params.refs
        );
        weth.withdraw(amountMinusFees);
        (bool success,) = msg.sender.call{value: amountMinusFees}("");
        require(success, "transfer");
        return amountMinusFees;
    }

    function swap(bytes calldata path, uint256 amountIn, uint256 quote, uint256 slippage, address to) internal returns (uint256 amountOut) {
        require(!lockSwap, "locked");
        lockSwap = true;
        address tokenIn = address(bytes20(path[0:20]));
        TransferHelper.safeApprove(address(tokenIn), address(swapRouter), amountIn);
        uint256 amountOutMinimum = quote * slippage / 10000;
        IV3SwapRouter.ExactInputParams memory params =
            IV3SwapRouter.ExactInputParams({
                path: path,
                //deadline: block.timestamp + 1 minutes,
                recipient: to,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum
            });

        amountOut = swapRouter.exactInput(params);
        lockSwap = false;
    }

    function distributeFees(
        uint256 amount,
        address trenchOwner,
        address[] calldata refs
    ) internal returns (uint256) {
        require(refs.length <= 4);
        uint256 baseFee = amount / fees[0]; // fees[0] is 100 by default
        uint256 trenchOwnerFee = baseFee * fees[1] / 100;
        uint256 teamFee = baseFee * fees[2] / 100;
        uint256[] memory refFees = new uint256[](4);

        if (refs.length > 0) {
            uint256[4] memory percentages = [fees[3], fees[4], fees[5], fees[6]];
            for (uint256 i = 0; i < refs.length; i++) {
                if(refs[i] == address(0) || percentages[i] == 0) continue;
                refFees[i] = baseFee * percentages[i] / 100;
                if (refFees[i] == 0) continue;
                console.log(IERC20(weth).balanceOf(address(this)), refFees[i]);
                weth.safeTransfer(refs[i], refFees[i]);
                teamFee -= refFees[i];
            }
        }

        if (trenchOwner != address(0)) {
            weth.safeTransfer(trenchOwner, trenchOwnerFee);
            weth.safeTransfer(team, teamFee);
        } else {
            weth.safeTransfer(team, teamFee + trenchOwnerFee);
        }

        return amount - baseFee;
    }

    function setTeamAddress(address _team) public onlyOwner {
        require(_team != address(0));
        team = _team;
    }

    function setMinBuy(uint256 _buy) public onlyOwner {
        require(_buy > 0 && _buy < 1 ether, "RANGE");
        minBuy = _buy;
    }

    function setFees(
        uint256 _base,
        uint256 _trenchOwner,
        uint256 _team,
        uint256 _ref1,
        uint256 _ref2,
        uint256 _ref3,
        uint256 _ref4
    ) external onlyOwner {
        require(_base >= 50, "max 2% total fee"); // 2% = 1/50 minimum
        require(_trenchOwner + _team + _ref1 + _ref2 + _ref3 + _ref4 <= 100, "invalid fee");
        fees[0] = _base;
        fees[1] = _trenchOwner;
        fees[2] = _team;
        fees[3] = _ref1;
        fees[4] = _ref2;
        fees[5] = _ref3;
        fees[6] = _ref4;
    }

    receive() external payable {
        // to handle WETH unwraps
    }
}
