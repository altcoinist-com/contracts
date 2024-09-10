pragma solidity ^0.8.20;
pragma abicoder v2;
import "forge-std/Test.sol";
import "forge-std/console.sol";
import '@uniswap/v3-periphery/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/libraries/TransferHelper.sol';

import "../src/ALTT.sol";
import "../src/SubscribeRegistry.sol";
import "../src/StakingFactory.sol";
import "../src/StakingVault.sol";
import "../src/CreatorTokenFactory.sol";

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


contract TestEnv is Test {
    ALTT public altt;
    SubscribeRegistry public registry;
    StakingVault public vaultImpl;
    StakingFactory public stakingFactory;
    CreatorTokenFactory public creatorFactory;
    TWAP public twap;
    IERC20 public weth = IERC20(0x4200000000000000000000000000000000000006);
    ISwapRouter public swapRouter = ISwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481); // mainnet
    //ISwapRouter public swapRouter = ISwapRouter(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4); // sepolia
    address[] public accounts = [
            0xE0342eaE75E695060d095d6aB6861C12FA0687e5,
            0x533DBa893ef7D1B86674Ba0B7Ec97484247D2561, // alice
            0xb4ca3d35f2530D831710177B554690619db6F2DE, // bob
            0x956C8546DcA181e28416c8b58331e61108d18C11, // carol
            0x22b2BDe5E51703F94292ef575387D0c1854c733A, // dave
            0xCA4b2DD3Ba6A835aaF92C194994c3a6cdFBf808C, // eve
            0xD4F12096B9Bb38dA388b59a718DACdca7f7D8B13,
            0xffF9a5E6939D87A7A4045CCf20bB3eaD03853bdA,
            0x6D1143F6425670378FD87932480E3688a65dc54c,
            0xB4100a0569b34c8d9f22B48ea6067dC75E3a3743,
            0xB066259e4267dAd514aAb33935299903Ed5aE0a5, // substakers
            0xb09ffabCDF88ea457591D5B30b070d06131b7Ed1,
            0x6AeC8BC3c479A09C71F87df88e160252394902Cf,
            0xF2546c8505d7bf58a5e13234e19154E03E9Aa80C,
            0x25a6127F46887597fC4722DeaDd207fb01fb0cd5,
            0xd7c0b72f0f41a829F4E16E36Ee524346864FE714,
            0x1B76dCBf949702faCF13EFD71Df42Afa02545026,
            0xA3F1029441Daa751363bDaCE95e65bf204cf0387,
            0x9024134660E12dD08a98e9DE6a4D203271E3FD57,
            0x35BE52CE7F847Dbf63597A138fb59fe5d4cFe08F
    ];

    constructor() {
        address ecosystem = 0xA6c0CCb2ba30F94b490d5b20d75d1f5330a6d2a3;
        vm.startPrank(accounts[0]);
        altt = new ALTT(accounts[0]);
        registry = new SubscribeRegistry(address(altt), ecosystem);
        vaultImpl = new StakingVault(IERC20(altt), registry);
        stakingFactory = new StakingFactory(address(registry), address(vaultImpl));
        creatorFactory = new CreatorTokenFactory(accounts[0], address(registry));
        VaultNotifier notifier = new VaultNotifier(address(stakingFactory));
        twap = new TWAP(accounts[0], address(altt), address(stakingFactory));
        registry.setFactories(address(stakingFactory), address(creatorFactory), address(notifier), address(twap));
        vm.stopPrank();
        bytes memory depositCall = abi.encodeWithSignature("deposit()");
        for(uint256 i=0; i<20; i++) {
            vm.startPrank(accounts[i]);
            (bool success, bytes memory data) = address(weth).call{value: 100e18}(depositCall);
            require(success, "deposit error");
            weth.approve(address(registry), 100e18);
            assertEq(weth.balanceOf(accounts[i]), 100e18);
            assertEq(weth.allowance(accounts[i], address(registry)), 100e18);
            altt.approve(address(registry), 1000000e18);
            assertEq(altt.allowance(accounts[i], address(registry)), 1000000e18);
            vm.stopPrank();
        }
        vm.startPrank(accounts[0]);
        weth.transfer(address(altt), 100e18);
    }

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
        vm.startPrank(accounts[0]);
        address nonfungiblePositionManager = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1; // mainnet
        //address nonfungiblePositionManager = 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2; // sepolia
        address WETH = 0x4200000000000000000000000000000000000006;
        deal(address(WETH), accounts[0], 1e20);

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
                recipient: accounts[0], // FIXME only for test!
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = NFTManager(nonfungiblePositionManager).mint(params);
        // Remove allowance and refund in both assets.

        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(address(WETH), address(nonfungiblePositionManager), 0);
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(address(WETH), accounts[0], refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(address(altt), address(nonfungiblePositionManager), 0);
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(address(altt), accounts[0], refund1);
        }
        
    }

}
