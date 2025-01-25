// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "forge-std/console.sol";

interface IWETH {
    function deposit() external payable;
}

contract TradeManager is Ownable {
    using SafeERC20 for IERC20;

    struct Position {
        uint256 id;
        uint256 timestamp;
        bytes path;
        uint256 amount;
        address owner;
    }

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

    mapping (address => Position) positions;
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
    }

    function createPosition(
        CreatePositionParams calldata params
    ) external payable {
        require(params.amount >= minBuy, "MIN");
        require(msg.value >= params.amount, "VAL");
        weth.deposit{value: params.amount}();

        uint256 amountMinusFees = distributeFees(
            params.amount,
            params.trenchOwner,
            params.refs);

        uint256 amountOut = swap(params.path, amountMinusFees, params.quote, params.slippage, msg.sender);
        require(amountOut > 0, "SWAP");
    }

    function swap(bytes calldata path, uint256 amountIn, uint256 quote, uint256 slippage, address to) internal returns (uint256 amountOut) {
        require(!lockSwap, "locked");
        lockSwap = true;
        TransferHelper.safeApprove(address(weth), address(swapRouter), amountIn);
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
        uint256 baseFee = amount / 100;
        uint256 trenchOwnerFee = baseFee * 20 / 100;
        uint256 teamFee = baseFee * 80 / 100;
        uint256[] memory refFees = new uint256[](4);

        if (refs.length > 0) {
            uint256[4] memory percentages = [uint256(10), uint256(6), uint256(3), uint256(1)];
            for (uint256 i = 0; i < refs.length; i++) {
                if(refs[i] == address(0)) continue;
                refFees[i] = baseFee * percentages[i] / 100;
                console.log("sent %d to %s", refFees[i], refs[i]);
                IERC20(address(weth)).safeTransfer(refs[i], refFees[i]);
                teamFee -= refFees[i];
            }
        }
        IERC20((address(weth))).safeTransfer(trenchOwner, trenchOwnerFee);
        IERC20((address(weth))).safeTransfer(team, teamFee);
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
}
