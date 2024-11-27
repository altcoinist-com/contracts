// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ALTT.sol";
import "../src/SubscribeRegistry.sol";
import "../src/StakingFactory.sol";
import "../src/StakingVault.sol";
import "../src/CreatorTokenFactory.sol";
//import "../src/PaymentCollector.sol";
import "../src/PaymentCollectorV2.sol";
import "../src/TWAP.sol";
import "../src/XPRedeem.sol";

struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
}

        
interface NFTManager {
    function mint(
        MintParams memory params
    ) external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function createAndInitializePoolIfNecessary(
        address tokenA,
        address tokenB,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external returns (address pool);
}



contract DeployAltt is Script {
        address admin = 0xB238cc95d463272b4a4ae0FdA6DdC5ebEC83B8D9;
        ALTT altt = ALTT(0xa3c51323b901b6D5f8d484e13DFC1a6F47dEb598);
        function addLiquidity()
                public
                returns (
                        address pool,
                        uint256 tokenId,
                        uint128 liquidity,
                        uint256 amount0,
                        uint256 amount1
                )
        {
                //address nonfungiblePositionManager = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1; // mainnet
                address nonfungiblePositionManager = 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2; // sepolia
                address WETH = 0x4200000000000000000000000000000000000006;


                pool = NFTManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
                        WETH,
                        address(altt),
                        100,
                        27445440573005958774799485370368 // $0.02 @ 3000 USD/WETH
                        //45742400955009929883957592064 // $1000
                        //792281625142643375935439503360 // test1
                        //158456325028528675187087900672000 // test2
                );
                require(pool != address(0));
                uint256 amount0ToMint = 1e20;
                uint256 amount1ToMint = 4e7 * 10 ** altt.decimals();

                // Approve the position manager
                TransferHelper.safeApprove(WETH, address(nonfungiblePositionManager), amount0ToMint);
                TransferHelper.safeApprove(address(altt), address(nonfungiblePositionManager), amount1ToMint);

                MintParams memory params =
                        MintParams({
                                token0: WETH,
                                token1: address(altt),
                                fee: 100,
                                tickLower: -887220, // TickMath.MIN_TICK https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol#L9C40-L9C47
                                tickUpper: 887220, // TickMath.MAX_TICK both rounded to a multiple of 60 (tickSpacing) => 887220
                                amount0Desired: amount0ToMint,
                                amount1Desired: amount1ToMint,
                                amount0Min: 0, // FIXME MEV
                                amount1Min: 0, // FIXME MEV
                                recipient: admin, // FIXME only for test!
                                deadline: block.timestamp
                        });

                (tokenId, liquidity, amount0, amount1) = NFTManager(nonfungiblePositionManager).mint(params);
                // Remove allowance and refund in both assets.

                if (amount0 < amount0ToMint) {
                        TransferHelper.safeApprove(address(WETH), address(nonfungiblePositionManager), 0);
                        uint256 refund0 = amount0ToMint - amount0;
                        TransferHelper.safeTransfer(address(WETH), admin, refund0);
                }

                if (amount1 < amount1ToMint) {
                        TransferHelper.safeApprove(address(altt), address(nonfungiblePositionManager), 0);
                        uint256 refund1 = amount1ToMint - amount1;
                        TransferHelper.safeTransfer(address(altt), admin, refund1);
                }

        }

        function run() external {
                vm.startBroadcast();
                altt.mint();
                require(altt.balanceOf(admin) == altt.totalSupply(), "balance");
                (address pool,,,,) = addLiquidity();
                console.log("Pool created %s", pool);
                require(altt.isAfterLP(), "no lp");
                vm.stopBroadcast();
        }
}
