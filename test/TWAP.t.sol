// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "./TestEnv.t.sol";
import {TWAP} from "../src/TWAP.sol";
import "../src/StakingVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract TWAPTest is Test {
    TestEnv env;
    StakingVault vault;
    IERC20 weth;
    ALTT altt;
    SubscribeRegistry registry;
    address alice;
    address bob;
    TWAP twap;
    function setUp() public {
        env = new TestEnv();
        StakingFactory stakingFactory = env.stakingFactory();
        altt = env.altt();
        registry = env.registry();
        twap = env.twap();
        vm.startPrank(env.accounts(1));
        registry.setSubPrice(1e18, 5e18, "JSmith");
        address vaultAddr = env.stakingFactory().vaults(env.accounts(1));
        assertTrue(vaultAddr != address(0), "uninitialized vault");
        vault = StakingVault(vaultAddr);
        assertEq(vault.name(), "JSmith ALTT staking pool");
        vm.stopPrank();

        
        console.log("twap address is %s", address(twap));
        weth = env.weth();
        require(address(weth) != address(0));
        alice = env.accounts(1);
        bob = env.accounts(2);
    }

    // tge not only checks the total supply
    // but also the existence of an LP pool after
    // IDO
    function tge() public {
        vm.stopPrank();
        vm.startPrank(env.accounts(0));
        vm.warp(block.timestamp + 90 days); // we can only init tge in 3 months
        env.altt().mint();
        vm.stopPrank();
        vm.startPrank(env.accounts(0));
        for (uint256 i=1; i<10; i++) {
            altt.transfer(env.accounts(i), 1000000 * 1e18);
        }
        (address pool,,,,) = env.addLiquidity();
    }

    function createVault(string memory label, uint256 price) public returns (address) {
        address author = makeAddr(label);
        deal(author, 1e18);
        deal(address(weth), author, price + 1e18); // dynamic sub price + 1weth stake
        vm.startPrank(author);
        registry.setSubPrice(price, price*2, label);
        address vaultAddr = env.stakingFactory().vaults(author);
        assertTrue(vaultAddr != address(0), "uninitialized vault");
        return vaultAddr;
    }

    function createSubber(string memory label, address author) public returns (address) {
        address subber = makeAddr(label);
        deal(subber, 10e18);

        uint256 price = registry.getSubPrice(author, SubscribeRegistry.packages.MONTHLY);
        deal(address(weth), subber, price + 2e18);
        
        vm.startPrank(subber);
        weth.approve(address(registry), type(uint256).max);
        assertEq(weth.allowance(subber, address(registry)), type(uint256).max);
        registry.subscribe(SubscribeRegistry.SubscribeParams(author, subber, SubscribeRegistry.packages.MONTHLY, 1, 1e18, address(0)));
        return subber;
    }

    function supplyWETH(address _vault) public {
        vm.warp(block.timestamp + 1 seconds);
        vm.startPrank(env.accounts(9));
        StakingVault(_vault).initWethConversion();
        //vm.startPrank(env.accounts(0));
    }


    function test_onlyVaultCanSupply() public {
        address attacker = makeAddr("bog");
        deal(attacker, 1e18);
        deal(address(weth), attacker, 1e18);

        vm.startPrank(attacker);
        vm.expectRevert();
        twap.supplyWETH(0.9e18);
    }

    function testFuzz_supplyWeth(uint256 amount) public {
        amount = bound(amount, 1e18, 100e18);
        address subber = createSubber("subber1", alice);
        assertGt(weth.balanceOf(address(vault)), 0);
        tge();
        vm.startPrank(env.accounts(0));
        twap.startTWAP();
        supplyWETH(address(vault));

        assertGt(weth.balanceOf(address(twap)), 0);
        assertEq(weth.balanceOf(address(twap)), twap.wethSum());
    }

    function test_cannotIterateBeforeStart() public {
        vm.startPrank(env.accounts(0));
        vm.expectRevert(bytes("not yet"));
        twap.iterateTWAP(0, type(uint256).max);

        tge();
        vm.startPrank(env.accounts(0));
        twap.startTWAP();

    }

    function test_cannotIterateBeforePeriodTick() public {
        vm.startPrank(env.accounts(0));
        vm.expectRevert(bytes("not yet"));
        twap.iterateTWAP(0, type(uint256).max);
        address subber = createSubber("subber1", alice);
        tge();
        vm.startPrank(env.accounts(0));
        twap.startTWAP();
        vm.warp(block.timestamp + 1 seconds);
        supplyWETH(address(vault));

        vm.startPrank(env.accounts(0));
        vm.warp(block.timestamp + 1 minutes);
        vm.expectRevert(bytes("interval"));
        twap.iterateTWAP(0, type(uint256).max);
    }

    function test_canIterateBeforePeriodTick_0vaults() public {
        vm.startPrank(env.accounts(0));
        vm.expectRevert(bytes("not yet"));
        twap.iterateTWAP(0, type(uint256).max);

        address subber = createSubber("subber1", alice);
        tge();
        vm.startPrank(env.accounts(0));
        twap.startTWAP();
        supplyWETH(address(vault));
        vm.warp(block.timestamp + 30 minutes + 1 seconds);
        vm.startPrank(env.accounts(0));
        twap.iterateTWAP(0, 10);
    }

    function testFuzz_periods_correct(uint256 price1, uint256 price2, uint256 price3) public {
        price1 = bound(price1, 1e18, 10e18);
        price2 = bound(price2, 1e18, 10e18);
        price3 = bound(price3, 1e18, 10e18);
        // createVault returns the POOL address not the creator!
        address vault1 = createVault("vault1", price1);
        address vault2 = createVault("vault2", price2);
        address vault3 = createVault("vault3", price3);

        // but makeAddr with the same label returns the CREATOR
        {
        address subber1 = createSubber("subber1", makeAddr("vault1"));
        address subber2 = createSubber("subber2", makeAddr("vault2"));
        address subber3 = createSubber("subber3", makeAddr("vault3"));
        }

        assertGt(weth.balanceOf(vault1), 0);
        assertGt(weth.balanceOf(vault2), 0);
        assertGt(weth.balanceOf(vault3), 0);

        tge();
        vm.startPrank(env.accounts(0));
        twap.startTWAP();

        supplyWETH(address(vault)); // for alice we set up in the constructor
        supplyWETH(vault1);
        supplyWETH(vault2);
        supplyWETH(vault3);
        
        vm.startPrank(env.accounts(0));

        // day 1
        uint256 wethBefore = weth.balanceOf(address(twap));
        console.log("test start %d", wethBefore);
        for(uint256 i=0; i<48; i++) {
            vm.warp(block.timestamp + 1801 seconds);
            uint256 balanceBefore = altt.balanceOf(vault1);
            uint256 amountOut = twap.iterateTWAP(0, 10);
            uint256 balanceAfter = altt.balanceOf(vault1);
            uint256 v1_v2_ratio = (price1 * 1e24) / price2;
            uint256 v2_v3_ratio = (price2 * 1e24) / price3;
            uint256 v1_v3_ratio = (price1 * 1e24) / price3;
            assertApproxEqAbs(altt.balanceOf(vault1), altt.balanceOf(vault2) * v1_v2_ratio / 1e24, 0.01e18);
            assertApproxEqAbs(altt.balanceOf(vault2), altt.balanceOf(vault3) * v2_v3_ratio / 1e24, 0.01e18);
            assertApproxEqAbs(altt.balanceOf(vault1), altt.balanceOf(vault3) * v1_v3_ratio / 1e24, 0.01e18);
        }

        assertGt(altt.balanceOf(vault1), 0);
        assertApproxEqAbs(wethBefore - weth.balanceOf(address(twap)), (wethBefore*5)/100, 1e17);

        // day 2 & 3
        //wethBefore = weth.balanceOf(address(twap));
        for(uint256 i=0; i<192; i++) {
            vm.warp(block.timestamp + 901 seconds);
            uint256 balanceBefore = altt.balanceOf(vault1);
            uint256 amountOut = twap.iterateTWAP(0, 10);
            uint256 balanceAfter = altt.balanceOf(vault1);
            uint256 v1_v2_ratio = (price1 * 1e24) / price2;
            uint256 v2_v3_ratio = (price2 * 1e24) / price3;
            uint256 v1_v3_ratio = (price1 * 1e24) / price3;
            assertApproxEqAbs(altt.balanceOf(vault1), altt.balanceOf(vault2) * v1_v2_ratio / 1e24, 0.01e18);
            assertApproxEqAbs(altt.balanceOf(vault2), altt.balanceOf(vault3) * v2_v3_ratio / 1e24, 0.01e18);
            assertApproxEqAbs(altt.balanceOf(vault1), altt.balanceOf(vault3) * v1_v3_ratio / 1e24, 0.01e18);
        }

        assertApproxEqAbs(wethBefore - weth.balanceOf(address(twap)), (wethBefore*65)/100, 1e17);

        // day 4 - 7
        //wethBefore = weth.balanceOf(address(twap));
        for(uint256 i=0; i<576; i++) {
            vm.warp(block.timestamp + 601 seconds);
            uint256 balanceBefore = altt.balanceOf(vault1);
            uint256 amountOut = twap.iterateTWAP(0, 10);
            uint256 balanceAfter = altt.balanceOf(vault1);
            uint256 v1_v2_ratio = (price1 * 1e24) / price2;
            uint256 v2_v3_ratio = (price2 * 1e24) / price3;
            uint256 v1_v3_ratio = (price1 * 1e24) / price3;
            assertApproxEqAbs(altt.balanceOf(vault1), altt.balanceOf(vault2) * v1_v2_ratio / 1e24, 0.01e18);
            assertApproxEqAbs(altt.balanceOf(vault2), altt.balanceOf(vault3) * v2_v3_ratio / 1e24, 0.01e18);
            assertApproxEqAbs(altt.balanceOf(vault1), altt.balanceOf(vault3) * v1_v3_ratio / 1e24, 0.01e18);
        }

        assertApproxEqAbs(weth.balanceOf(address(twap)), 0, 1e17);
    }

    function test_midwayWETHSupply() public {
        uint256 price1 = 1e18;
        uint256 price2 = 2e18;
        uint256 price3 = 3e18;


        address vault1 = createVault("vault1", price1);
        address vault2 = createVault("vault2", price2);
        address vault3 = createVault("vault3", price3);
        address vault4 = createVault("vault4", price3);


        {
        address subber1 = createSubber("subber1", makeAddr("vault1"));
        address subber2 = createSubber("subber2", makeAddr("vault2"));
        address subber3 = createSubber("subber3", makeAddr("vault3"));
        address subber4 = createSubber("subber4", makeAddr("vault4"));
        }
        
        
        assertGt(weth.balanceOf(vault1), 0);
        assertGt(weth.balanceOf(vault2), 0);
        assertGt(weth.balanceOf(vault3), 0);

        tge();
        vm.startPrank(env.accounts(0));
        twap.startTWAP();

        supplyWETH(vault1);
        supplyWETH(vault2);
        supplyWETH(vault3);

        vm.startPrank(env.accounts(0));

        // day 1
        uint256 wethBefore = weth.balanceOf(address(twap));
        console.log("test start %d", wethBefore);

        vm.warp(block.timestamp + 1801 seconds);
        uint256 balanceBefore = altt.balanceOf(vault1);
        vm.expectRevert(bytes("missing pool"));
        uint256 amountOut = twap.iterateTWAP(0, 10);

    }


}
