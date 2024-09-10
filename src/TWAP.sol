// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "../src/ALTT.sol";
import "../src/StakingFactory.sol";
import {StakingVault} from "../src/StakingVault.sol";
import {SubscribeRegistry} from "../src/SubscribeRegistry.sol";
import "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract TWAP is Ownable {
    using Math for uint256;
    using SafeERC20 for IERC20;
    ALTT public immutable altt;
    IV3SwapRouter public immutable swapRouter;
    IERC20 public immutable weth;
    StakingFactory immutable factory;
    address immutable self;
    bool lockSwap;
    struct TWAPShare {
        address pool;
        uint256 timestamp;
        uint256 wethAmount;
    }

    TWAPShare[] public shares;
    mapping (address => bool) conversionStarted;
    uint256 public lastIter;
    uint256 periodStart;

    uint256 public wethSum;
    uint256 public vaultsSupplied;

    constructor(
        address _owner,
        address _altt,
        address _factory

    ) Ownable(_owner) {
        require(_altt != address(0) && _factory != address(0) && _owner != address(0));
        weth = IERC20(0x4200000000000000000000000000000000000006);
        swapRouter = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481); // mainnet
        // swapRouter = IV3SwapRouter(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4); // sepolia
        altt = ALTT(_altt);
        factory = StakingFactory(_factory);
        self = address(this);
        wethSum = 0;
        lastIter = 0;
        vaultsSupplied = 0;
    }

    modifier onlyVault() {
        address creator = StakingVault(msg.sender).creator();
        require(factory.vaults(creator) == msg.sender, "PD");
        _;
    }

    event WETHSupplied(address pool, uint256 amount);
    function supplyWETH(uint256 amount) public onlyVault {
        require(altt.isAfterLP(), "TGEE");
        require(!conversionStarted[msg.sender], "already supplied");
        require(periodStart < block.timestamp && periodStart > 0, "not yet");
        weth.safeTransferFrom(msg.sender, self, amount);
        wethSum += amount;
        shares.push(TWAPShare(msg.sender, block.timestamp, amount));
        conversionStarted[msg.sender] = true;
        vaultsSupplied += 1;
        emit WETHSupplied(msg.sender, amount);
    }

    function startTWAP() public onlyOwner {
        require(periodStart == 0);
        periodStart = block.timestamp;
        lastIter = block.timestamp;
    }

    event TWAPIter(uint256 time, uint256 alttAmount);
    function iterateTWAP(uint256 skip, uint256 limit) public onlyOwner returns (uint256) {
        require(block.timestamp > periodStart && periodStart != 0, "not yet");
        require(IERC20(weth).balanceOf(self) > 0, "BAL");
        require(vaultsSupplied == SubscribeRegistry(factory.registry()).wethVaults(), "missing pool");
        uint256 periodAmount = 0;

        // period 1 - 5% total daily, 0.1% every 1800 sec
        if (block.timestamp > periodStart && block.timestamp < periodStart + 1 days) {
            require(block.timestamp - lastIter > 1800, "interval");
            periodAmount = wethSum.mulDiv(5, 48, Math.Rounding.Ceil) / 100;
        }
        // period 2 - 30% for 2 days, ~0.31% every 900 sec
        else if (block.timestamp >= periodStart + 1 days && block.timestamp < periodStart + 3 days) {
            require(block.timestamp - lastIter > 900, "interval");
            periodAmount = wethSum.mulDiv(60, 100, Math.Rounding.Ceil) / 192;
        }
        // period 3 - 8.75% daily, ~0.06% every 600 sec
        else if (block.timestamp >= periodStart + 3 days && block.timestamp < periodStart + 8 days) {
            require(block.timestamp - lastIter > 600, "interval");
            periodAmount = wethSum.mulDiv(35, 100, Math.Rounding.Ceil) / 576;
        } else {
            // periodAmount = IERC20(weth).balanceOf(self);
        }

        uint256 amountOut = swapWethForAltt(periodAmount);
        require(amountOut > 0 && altt.balanceOf(self) > 0, "SWAP");
        
        for(uint256 i=skip; i<Math.min(shares.length, skip+limit); i++) {
            uint256 ratio = shares[i].wethAmount.mulDiv(1e24, wethSum, Math.Rounding.Floor);
            uint256 out = Math.min(altt.balanceOf(self), (amountOut * ratio) / 1e24);
            IERC20(altt).safeTransfer(shares[i].pool, out);
        }

        lastIter = block.timestamp;
        emit TWAPIter(lastIter, amountOut);
        return amountOut;
    }

    function swapWethForAltt(uint256 amountIn) internal returns (uint256 amountOut) {
        require(!lockSwap, "locked");
        lockSwap = true;
        TransferHelper.safeApprove(address(weth), address(swapRouter), amountIn);
        IV3SwapRouter.ExactInputSingleParams memory params =
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(altt),
                fee: 100,
                recipient: self,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
        lockSwap = false;
    }

    function sharesLen() public view returns (uint256) {
        return shares.length;
    }

    function recoverFunds() public onlyOwner {
        require(block.timestamp > periodStart + 60 days, "not yet");
        uint256 wethBalance = IERC20(weth).balanceOf(self);
        uint256 alttBalance = IERC20(altt).balanceOf(self);
        IERC20(weth).safeTransfer(owner(), wethBalance);
        IERC20(altt).safeTransfer(owner(), alttBalance);
    }
}
