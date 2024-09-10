pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "./TestEnv.t.sol";
import "forge-std/console.sol";
import "../src/StakingVault.sol";
import "../src/ALTT.sol";

contract StakingVaultTest is Test {
    TestEnv env;
    StakingVault vault;
    StakingFactory stakingFactory;
    IERC20 weth = IERC20(0x4200000000000000000000000000000000000006);
    ALTT altt;
    SubscribeRegistry registry;
    uint256 constant ethusd = 120000000000;
    function setUp() public {
        env = new TestEnv();
        stakingFactory = env.stakingFactory();
        altt = env.altt();
        registry = env.registry();
        vm.startPrank(env.accounts(1));
        registry.setSubPrice(1e18, 5e18, "JSmith");
        address vaultAddr = env.stakingFactory().vaults(env.accounts(1));
        assertTrue(vaultAddr != address(0), "uninitialized vault");
        vault = StakingVault(vaultAddr);
        assertEq(vault.name(), "JSmith ALTT staking pool");
        vm.stopPrank();
    }

    // tge not only checks the total supply
    // but also the existence of an LP pool after
    // IDO
    function tge() public {
        vm.stopPrank();
        vm.startPrank(env.accounts(0));
        vm.warp(block.timestamp + 1 days); // we can only init tge in 3 months
        env.altt().mint();
        vm.stopPrank();
        vm.startPrank(env.accounts(0));
        for (uint256 i=1; i<10; i++) {
            altt.transfer(env.accounts(i), 1000000 * 1e18);
        }
        (address pool,,,,) = env.addLiquidity();
        vm.startPrank(env.accounts(0));
        require(altt.isAfterLP());
        vm.stopPrank();
    }

    /// forge-config: default.invariant.runs = 10
    /// forge-config: default.invariant.depth = 2
    function invariant_neverDecreaseValue() public {
        assertGe(vault.totalAssets(), vault.totalSupply());
    }

    function test_cantOpenPoolWithEOA() public {
        vm.startPrank(env.accounts(1));
        address bob = env.accounts(2);
        vm.expectRevert(bytes("PD"));
        stakingFactory.createPool(bob);
    }

    function test_cantStakeWithoutSub() public {
        tge();
        address bob = env.accounts(2);
        vm.startPrank(bob);
        vault = StakingVault(stakingFactory.vaults(env.accounts(1)));
        vm.expectRevert(bytes("PD"));
        vault.deposit(5e17, bob);
    }

    function test_cantStakeWETHWithoutSub() public {
        address bob = env.accounts(2);
        vm.startPrank(bob);
        vault = StakingVault(stakingFactory.vaults(env.accounts(1)));
        vm.expectRevert(bytes("PD"));
        vault.depositWeth(bob, 1e18);
    }

    function test_canStakeWithLifetimeNFT() public {
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        // subscribe to alice
        vm.startPrank(bob);
        weth.approve(address(vault), 1e18);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.LIFETIME, 1, 1e18, address(0)));
        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, type(uint256).max);
        uint256 lifetimePrice = registry.getSubPrice(alice, SubscribeRegistry.packages.LIFETIME);
        //assertApproxEqAbs(vault.totalAssets(), 1e18 + (((lifetimePrice*12)/100)*ethusd)/1e8, 0.005e18);
    }

    function test_cantStakePriorTGE() public {
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        // subscribe to alice
        vm.startPrank(bob);
        weth.approve(address(vault), 1e18);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        assertEq(env.creatorFactory().balanceOf(bob, uint256(uint160(alice))), 1, "StakingNFT");
        uint256 bobBalance = weth.balanceOf(bob);

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days);

        // stake 0.5WETH to alice
        vault = StakingVault(stakingFactory.vaults(alice));
        assertEq(vault.totalSupply(), 0, "103");
        vm.expectRevert(bytes("TGEE"));
        vault.deposit(1e18, bob);
    }

    function testFuzz_canStakeSeparateWETHPriorTGE(uint256 a) public {
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        a = bound(a, 1e16, 1e18);
        // subscribe to alice
        vm.startPrank(bob);
        weth.approve(address(vault), 1e18);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        assertEq(env.creatorFactory().balanceOf(bob, uint256(uint160(alice))), 1, "StakingNFT");
        uint256 bobBalance = weth.balanceOf(bob);

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 60 days);

        // stake 0.5WETH to alice
        vault = StakingVault(stakingFactory.vaults(alice));
        assertEq(vault.totalSupply(), 0);
        vault.depositWeth(bob, a);
        assertEq(vault.getWethDeposit(bob), a);
    }

    function testFuzz_canStakeJointWETHPriorTGE(uint256 a) public {
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        a = bound(a, 1e16, 1e18);
        // subscribe to alice
        vm.startPrank(bob);
        weth.approve(address(vault), 1e18);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, a, address(0)));
        assertEq(env.creatorFactory().balanceOf(bob, uint256(uint160(alice))), 1, "StakingNFT");
        uint256 bobBalance = weth.balanceOf(bob);

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days);
        assertEq(vault.getWethDeposit(bob), a);
    }

    function testFuzz_stakeSingleUserAndWithdraw(uint256 amount, uint256 d) public {
        amount = bound(amount, 1e18, 100e18);
        d = bound(d, 1, 180);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);

        // subscribe to alice
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.LIFETIME, 1, amount, address(0)));
        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, type(uint256).max);

        // stake to alice
        vault = StakingVault(stakingFactory.vaults(alice));
        uint256 shares = vault.balanceOf(bob);
        assertEq(vault.totalSupply(), shares, "a");
        assertEq(vault.getDeposit(bob), amount, "c");

        // generate yield to vault from carol
        vm.startPrank(carol);
        weth.approve(address(vault), 1e18);
        assertEq(weth.allowance(carol, address(vault)), 1e18);

        // spend 1 eth, swap 12 altt into pool
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        assertGt(vault.totalAssets(), amount);
        console.log("assets inside: %d", vault.totalAssets());
        // bob unstakes
        vm.stopPrank(); vm.startPrank(bob);
        uint256 maxRedeem = vault.maxRedeem(bob);
        assertGt(maxRedeem, 0, "maxredeem");
        assertEq(vault.maxWithdraw(bob), amount);
        uint256 received = vault.redeem(maxRedeem, bob, bob);

        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);
        uint256 lifetimePrice = registry.getSubPrice(alice, SubscribeRegistry.packages.LIFETIME);
        // we only get our original stake at the 0th day
        assertApproxEqAbs(received, amount, 0.05e18);

        vm.warp(block.timestamp + d*1 days);
        maxRedeem = vault.maxRedeem(bob);
        received = vault.redeem(maxRedeem, bob, bob);
        uint256 target = ((monthlyPrice*1200/10000) + (lifetimePrice*1200/10000));
        target = target*(d*1e18/180)/1e16; // apply vesting
        target = (target*ethusd)/1e8; // convert to ALTT
        assertGt(received, amount);
    }

    /* function randint() public returns (uint256) {
        string[] memory inputs = new string[](3);
        inputs[0] = "python";
        inputs[1] = "-c";
        inputs[2] = "import random;print(\"0x\"+\"0\"*63+str(random.randint(0,2)), end=\"\")";
        bytes memory res = vm.ffi(inputs);
        return abi.decode(res, (uint256));
    } */

    function getMonthlyPrice(address author) internal returns (uint256) {
        return registry.getSubPrice(author, SubscribeRegistry.packages.MONTHLY);
    }


    function testFuzz_stakeMultiUserAndWithdraw(uint256 amount, uint256 d) public {
        amount = bound(amount, 1e18, 100000e18);
        d = bound(d, 1, 365);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        SubscribeRegistry.packages package = SubscribeRegistry.packages.LIFETIME;
        uint256 packagePrice = registry.getSubPrice(alice, package);
        for (uint256 i=3; i<10; i++) {
            vm.startPrank(env.accounts(i));
            // subscribe to lifetime

            uint256 subberBefore = weth.balanceOf(env.accounts(i));
            registry.subscribe(SubscribeRegistry.SubscribeParams(alice, env.accounts(i), package, 1, amount, address(0)));
            uint256 subberAfter = weth.balanceOf(env.accounts(i));
            assertApproxEqAbs(subberBefore - subberAfter, packagePrice, 0.001e18);
            uint256 expiry = registry.getSubDetails(alice, env.accounts(i));
            uint256 expectedDeadline = type(uint256).max;
            assertEq(expiry, expectedDeadline);


            vault = StakingVault(stakingFactory.vaults(alice));
            assertGe(vault.totalAssets(), amount);

        }
        // expectedVaultBalance = (expectedVaultBalance * 12) / 100;
        // assertEq(altt.balanceOf(address(vault)), expectedVaultBalance);

        vm.warp(block.timestamp + d*1 days);
        for (uint256 i=3; i<9; i++) {
            address staker = env.accounts(i);
            assertGe(vault.maxWithdraw(staker), amount);
            vm.stopPrank(); vm.startPrank(staker);
            uint256 alttOut = vault.redeem(vault.maxRedeem(staker), staker, staker);
            assertGe(alttOut, amount);
        }

    }


    function testFuzz_stakeAndWithdrawAfterInactivity(uint256 amount, uint256 d) public {
        amount = bound(amount, 1e18, 100000e18);
        d = bound(d, 1, 365);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        // subscribe 1 month
        vm.startPrank(bob);
        SubscribeRegistry.packages package = SubscribeRegistry.packages.MONTHLY;
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, package, 1, amount, address(0)));
        vm.warp(block.timestamp + 30 days + 1 hours);
        uint256 maxWithdraw = vault.maxWithdraw(bob);
        uint256 maxRedeem = vault.maxRedeem(bob);
        assertEq(maxWithdraw, amount);
        // let the subscription expire (by d days)
        vm.warp(block.timestamp + d*1 days);

        // we did not accumulate reward during inactivity
        assertEq(maxRedeem, vault.maxRedeem(bob));

        //vault.redeem(maxRedeem, bob, bob);

        // resubscribe for 2 months
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, package, 2, amount, address(0)));
        // vesting restarted
        maxWithdraw = vault.maxWithdraw(bob);
        assertEq(vault.maxWithdraw(bob), 2*amount);
        maxRedeem = vault.maxRedeem(bob);

        // and continues from here...
        vm.warp(block.timestamp + 1 days);
        assertLt(maxRedeem, vault.maxRedeem(bob));
        assertLt(maxWithdraw, vault.maxWithdraw(bob));
        maxRedeem = vault.maxRedeem(bob);

        uint256 alttBefore = altt.balanceOf(bob);
        vault.redeem(maxRedeem, bob, bob);
        uint256 alttAfter = altt.balanceOf(bob);
        assertGt(alttAfter-alttBefore, amount, "asd");
    }

    function testFuzz_stakeAndWithdrawAfterUpgradeActive(uint256 amount, uint256 d) public {
        amount = bound(amount, 0.001e18, 100000e18);
        d = bound(d, 1, 365);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        // subscribe 1 month
        vm.startPrank(bob);
        SubscribeRegistry.packages package = SubscribeRegistry.packages.MONTHLY;
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, package, 1, amount, address(0)));
        vm.warp(block.timestamp + 10 days);

        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.LIFETIME, 1, 0, address(0)));
        assertEq(registry.getSubDetails(alice, bob), type(uint256).max);

        uint256 maxRedeem = vault.maxRedeem(bob);


        vm.warp(block.timestamp + d*1 days);
        assertGt(vault.maxRedeem(bob), maxRedeem);
        maxRedeem = vault.maxRedeem(bob);

        assertGt(vault.redeem(maxRedeem, bob, bob), amount);
    }

    function testFuzz_stakeAndWithdrawAfterUpgradeInactive(uint256 amount, uint256 d) public {
        amount = bound(amount, 1e18, 100000e18);
        d = bound(d, 1, 365);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        // subscribe 1 month
        vm.startPrank(bob);
        SubscribeRegistry.packages package = SubscribeRegistry.packages.MONTHLY;
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, package, 1, amount, address(0)));
        vm.warp(block.timestamp + 35 days);

        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.LIFETIME, 1, 0, address(0)));
        assertEq(registry.getSubDetails(alice, bob), type(uint256).max);

        uint256 maxRedeem = vault.maxRedeem(bob);

        vm.warp(block.timestamp + d*1 days);
        assertGt(vault.maxRedeem(bob), maxRedeem);
        maxRedeem = vault.maxRedeem(bob);

        assertGt(vault.redeem(maxRedeem, bob, bob), amount);
    }


    function test_wethConversionAfterTGE() public {
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);
        uint256 amount = 1e18;
        // subscribe to alice
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, amount, address(0)));
        uint256 bobBalance = weth.balanceOf(bob);
        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days, "timestamp");
        vault = StakingVault(stakingFactory.vaults(alice));

        vault = StakingVault(stakingFactory.vaults(alice));
        assertGt(weth.balanceOf(address(vault)), amount);


        // sub to alice with carol and generate yield for bob
        vm.stopPrank(); vm.startPrank(carol);
        assertEq(vault.totalSupply(), 0);
        weth.approve(address(vault), amount);
        assertEq(weth.allowance(carol, address(vault)), amount);

        uint256 wethBefore = weth.balanceOf(address(vault));
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        uint256 wethAfter = weth.balanceOf(address(vault));
        assertGt(wethAfter, wethBefore);
        console.log(wethAfter, wethBefore);

        tge();
        vm.startPrank(env.accounts(4));

        wethBefore = weth.balanceOf(address(vault));
        uint256 alttBefore = altt.balanceOf(address(vault));

        vm.startPrank(env.accounts(0));
        env.twap().startTWAP();
        vm.startPrank(env.accounts(9));
        vm.warp(block.timestamp + 1 seconds);
        vault.initWethConversion();

        vm.startPrank(env.accounts(0));
        vm.warp(block.timestamp + 1801 seconds);
        env.twap().iterateTWAP(0, 100);
        
        wethAfter = weth.balanceOf(address(vault));
        uint256 alttAfter = altt.balanceOf(address(vault));
        assertLt(wethAfter, wethBefore);
        assertGt(alttAfter, alttBefore);
    }


    function test_stakeWETHAndWithdraw(uint256 a, uint256 d) public {
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        a = bound(a, 1e16, 1e18);
        d = bound(d, 1, 100);

        // subscribe to alice
        vm.startPrank(bob);
        weth.approve(address(vault), 1e18);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, a, address(0)));
        assertEq(env.creatorFactory().balanceOf(bob, uint256(uint160(alice))), 1, "StakingNFT");
        uint256 bobBalance = weth.balanceOf(bob);

        assertEq(registry.getSubDetails(alice, bob), block.timestamp + 30 days);

        vault = StakingVault(stakingFactory.vaults(alice));
        assertEq(vault.getWethDeposit(bob), a);

        // withdraw
        tge();
        vm.warp(block.timestamp + d*1 days);

        vm.startPrank(env.accounts(0));
        env.twap().startTWAP();
        vm.startPrank(env.accounts(9));
        vm.warp(block.timestamp + 1 seconds);
        vault.initWethConversion();

        vm.startPrank(env.accounts(0));
        vm.warp(block.timestamp + 1801 seconds);
        env.twap().iterateTWAP(0, 100);

        uint256 wethBefore = weth.balanceOf(bob);
        vm.startPrank(bob);
        vault.withdrawWeth(a);
        uint256 wethAfter = weth.balanceOf(bob);

        assertEq(wethAfter - wethBefore, a);

    }

    function testFuzz_stakeMultiUserMonthlyGetInitialDeposit(uint256 amount) public {
        // In this scenario, each user stakes in (monthly), the takes out
        // stake amount at the 0th day and then redeem only
        // rewards according to the vesting schedule
        amount = bound(amount, 1e11, 10e18);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        SubscribeRegistry.packages package = SubscribeRegistry.packages.MONTHLY;
        uint256 packagePrice = registry.getSubPrice(alice, package);
        for (uint256 i=3; i<10; i++) {
            vm.startPrank(env.accounts(i));
            // subscribe to lifetime

            uint256 subberBefore = weth.balanceOf(env.accounts(i));
            registry.subscribe(SubscribeRegistry.SubscribeParams(alice, env.accounts(i), package, 1, amount, address(0)));
            uint256 subberAfter = weth.balanceOf(env.accounts(i));
            assertApproxEqAbs(subberBefore - subberAfter, packagePrice, 0.001e18);
            uint256 expiry = registry.getSubDetails(alice, env.accounts(i));
            uint256 expectedDeadline = block.timestamp + 30 days;
            assertEq(expiry, expectedDeadline);

            vault = StakingVault(stakingFactory.vaults(alice));
            assertGe(vault.totalAssets(), amount);

        }
        // expectedVaultBalance = (expectedVaultBalance * 12) / 100;
        // assertEq(altt.balanceOf(address(vault)), expectedVaultBalance);


        for (uint256 i=3; i<10; i++) {
            address staker = env.accounts(i);
            vm.stopPrank(); vm.startPrank(staker);
            assertEq(vault.maxWithdraw(staker), amount, "withdraw");
            assertGt(vault.maxRedeem(staker), 0);
            uint256 alttOut = vault.redeem(vault.maxRedeem(staker), staker, staker);
            assertApproxEqAbs(alttOut, amount, 0.0001e18);
        }

    }

    function testFuzz_stakeMultiUserMonthlyGetInitialDepositDelayed(uint256 amount) public {
        // In this scenario, each user stakes in (monthly), the takes out
        // stake amount at the 0th day and then redeem only
        // rewards according to the vesting schedule
        amount = bound(amount, 1e11, 10000e18);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);
        SubscribeRegistry.packages package = SubscribeRegistry.packages.MONTHLY;
        uint256 packagePrice = registry.getSubPrice(alice, package);

        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, package, 1, amount, address(0)));
        vm.warp(block.timestamp + 250 days);

        vm.startPrank(carol);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, package, 2, amount, address(0)));

        vm.warp(block.timestamp + 30 days);

        vm.startPrank(bob);

        vault = StakingVault(stakingFactory.vaults(alice));
        uint256 balanceBefore = altt.balanceOf(bob);
        vault.withdraw(amount, bob, bob);
        uint256 balanceAfter = altt.balanceOf(bob);
        assertEq(balanceAfter - balanceBefore, amount);
    }


    function testFuzz_stakeMultiUserLifetimeGetInitialDeposit(uint256 amount) public {
        // In this scenario, each user stakes in lifetime, the takes out
        // stake amount at the 0th day and then redeem only
        // rewards according to the vesting schedule
        amount = bound(amount, 1e11, 10e18);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        SubscribeRegistry.packages package = SubscribeRegistry.packages.LIFETIME;
        uint256 packagePrice = registry.getSubPrice(alice, package);
        for (uint256 i=3; i<10; i++) {
            vm.startPrank(env.accounts(i));
            // subscribe to lifetime

            uint256 subberBefore = weth.balanceOf(env.accounts(i));
            registry.subscribe(SubscribeRegistry.SubscribeParams(alice, env.accounts(i), package, 1, amount, address(0)));
            uint256 subberAfter = weth.balanceOf(env.accounts(i));
            assertApproxEqAbs(subberBefore - subberAfter, packagePrice, 0.001e18);
            uint256 expiry = registry.getSubDetails(alice, env.accounts(i));
            uint256 expectedDeadline = type(uint256).max;
            assertEq(expiry, expectedDeadline);

            vault = StakingVault(stakingFactory.vaults(alice));
            assertGe(vault.totalAssets(), amount);

        }
        // expectedVaultBalance = (expectedVaultBalance * 12) / 100;
        // assertEq(altt.balanceOf(address(vault)), expectedVaultBalance);


        for (uint256 i=3; i<10; i++) {
            address staker = env.accounts(i);
            vm.stopPrank(); vm.startPrank(staker);
            assertEq(vault.maxWithdraw(staker), amount, "withdraw");
            assertGt(vault.maxRedeem(staker), 0, "redeem");
            assertGe(vault.balanceOf(staker), vault.maxRedeem(staker), "balance");

            uint256 stakerBefore = altt.balanceOf(staker);
            uint256 amountWanted = vault.maxWithdraw(staker);
            uint256 alttOut = vault.withdraw(amountWanted, staker, staker);
            uint256 stakerAfter = altt.balanceOf(staker);
            assertApproxEqAbs(stakerAfter - stakerBefore, amount, 0.0001e18, "amount");
            console.log(vault.totalAssets(), vault.totalSupply());
        }

    }

    function test_authorCanTopupAltt() public {
        tge();
        address alice = env.accounts(1);
        vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(alice);
        env.altt().transfer(address(vault), 10e18);
        assertEq(vault.totalAssets(), 10e18);
        assertEq(vault.totalSupply(), 0);
    }

    function test_authorCanTopupWeth() public {
        address alice = env.accounts(1);
        vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(alice);
        weth.approve(address(vault), 1e18);
        vault.depositWeth(address(vault), 1e18);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(weth.balanceOf(address(vault)), 1e18);
    }

    function test_vaultTokenIsSoulBound() public {
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);
        vault = StakingVault(stakingFactory.vaults(alice));
        SubscribeRegistry.packages package = SubscribeRegistry.packages.LIFETIME;
        uint256 packagePrice = registry.getSubPrice(alice, package);

        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, package, 1, 1e18, address(0)));

        uint256 bobBalance = vault.balanceOf(bob);
        vm.expectRevert("soulbound");
        vault.transfer(carol, bobBalance);
    }

    function test_rewardsWithdrawnSlashedRedeposit(uint256 amount, uint256 d) public {
        amount = bound(amount, 1e11, 100000e18);
        d = bound(d, 1, 1800);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);
        address dave = env.accounts(4);
        // subscribe to alice from dave
        vm.startPrank(dave);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, dave, SubscribeRegistry.packages.LIFETIME, 1, amount, address(0)));

        vm.warp(block.timestamp + 250 days);

        // subscribe to alice from bob, resulting in a share slash
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, amount, address(0)));


        assertLt(vault.balanceOf(bob), amount);
        assertLt(vault.balanceOf(bob), vault.balanceOf(dave));
        vm.warp(block.timestamp + 180 days);

        // bob subscribes and deposits again
        vm.stopPrank(); vm.startPrank(bob);

        uint256 alttBefore = altt.balanceOf(bob);
        uint256 maxWithdraw = vault.maxWithdraw(bob);
        uint256 poolBefore = vault.totalAssets();

        altt.approve(address(vault), type(uint256).max);
        assertEq(type(uint256).max, altt.allowance(bob, address(vault)));
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 7, 1e11,  address(0)));

        vm.warp(block.timestamp + 190 days);

        uint256 alttAfter = altt.balanceOf(bob);
        uint256 poolAfter = vault.totalAssets();

        //assertApproxEqAbs(alttAfter - alttBefore, maxWithdraw - 1e17, 0.0001e18);
        //assertApproxEqAbs(poolAfter, poolBefore - maxWithdraw + 1e17, 0.3e18);
        assertLt(vault.unlockedRewards(bob), vault.unlockedRewards(dave));

    }

     function test_rewardsWithdrawnOnRedeposit(uint256 amount, uint256 d) public {
        amount = bound(amount, 1e11, 100e18);
        d = bound(d, 1, 180);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);

        // subscribe to alice
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.LIFETIME, 1, amount, address(0)));
        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, type(uint256).max);

        // generate yield to vault from carol
        vm.stopPrank(); vm.startPrank(carol);
        weth.approve(address(vault), 1e18);
        assertEq(weth.allowance(carol, address(vault)), 1e18);

        // spend 1 eth, swap 12 altt into pool
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        assertGt(vault.totalAssets(), amount);

        uint256 packagePrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        vm.warp(block.timestamp + d*1 days);

        // bob deposits again
        vm.stopPrank(); vm.startPrank(bob);

        uint256 alttBefore = altt.balanceOf(bob);
        uint256 maxWithdraw = vault.maxWithdraw(bob);
        uint256 unlocked = vault.unlockedRewards(bob);
        assertGe(maxWithdraw, amount);
        uint256 poolBefore = vault.totalAssets();

        altt.approve(address(vault), 1e11);
        vault.deposit(1e11, bob); // should get you back rewards unlocked so far

        uint256 alttAfter = altt.balanceOf(bob);
        uint256 poolAfter = vault.totalAssets();

        
        assertApproxEqAbs(alttAfter - alttBefore, unlocked, 1e14);

        assertApproxEqAbs(poolAfter, poolBefore - unlocked + 1e11, 1e14);
    }

    function testFuzz_rewardsObservedAfterRedeposit(uint256 amount, uint256 d) public {
        amount = bound(amount, 1e11, 100e18);
        d = bound(d, 1, 365*10);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);

        // subscribe to alice from carol
        vm.startPrank(carol);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.LIFETIME, 1, amount, address(0)));

        // subscribe to alice from bob
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, amount, address(0)));
        console.log("bob 1st %d", vault.balanceOf(bob));

        assertApproxEqAbs(vault.balanceOf(carol), vault.balanceOf(bob), 0.00001e18);
        vm.warp(block.timestamp + 20 days);

        vm.startPrank(env.accounts(0));
        altt.transfer(address(vault), 1000e18);
        uint256 bobExpired = vault.unlockedRewards(bob);
        vm.warp(block.timestamp + 180 days); // bob expired here

        vm.startPrank(env.accounts(0)); // more rewards in pool, bob shouldn't see this
        altt.transfer(address(vault), 1000e18);
        //console.log("rewards %d", vault.unlockedRewards(bob) + vault.unlockedRewards(carol));
        assertEq(vault.unlockedRewards(bob), 0, "expired");
        // bob resubscribes
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 7, amount, address(0)));
        console.log("bob 2nd %d", vault.balanceOf(bob));
        vm.warp(block.timestamp + 190 days);
        vm.startPrank(env.accounts(0));
        altt.transfer(address(vault), 1000e18);

        assertLt(vault.unlockedRewards(bob), vault.unlockedRewards(carol));
    }

   function testFuzz_canStakeWETHPosteriorTGE(uint256 a) public {
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);

        a = bound(a, 1e16, 1e18);
        // subscribe to alice
        vm.startPrank(bob);
        weth.approve(address(vault), 1e18);
        altt.approve(address(vault), type(uint256).max);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        assertEq(env.creatorFactory().balanceOf(bob, uint256(uint160(alice))), 1, "StakingNFT");
        uint256 bobBalance = weth.balanceOf(bob);

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 60 days);

        // stake 0.5WETH to alice
        vault = StakingVault(stakingFactory.vaults(alice));
        assertEq(vault.totalSupply(), 0);
        vault.depositWeth(bob, a);
        assertEq(vault.getWethDeposit(bob), 0);
        console.log("bob has %d shares", vault.balanceOf(bob));
        assertGt(vault.balanceOf(bob), 0);
    }

   function testFuzz_rewardsObservedAfterRedepositWETH(uint256 amount, uint256 d) public {
        amount = bound(amount, 1e18, 2e18);
        d = bound(d, 1, 365*10);
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);

        // subscribe to alice from carol
        vm.startPrank(carol);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.LIFETIME, 1, amount, address(0)));

        // subscribe to alice from bob
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, amount, address(0)));
        
        vm.warp(block.timestamp + 20 days);

        vm.startPrank(env.accounts(0));
        altt.transfer(address(vault), 1000e18);

        vm.warp(block.timestamp + 180 days); // bob expired here

        vm.startPrank(env.accounts(0)); // more rewards in pool, bob shouldn't see this
        altt.transfer(address(vault), 1000e18);
        console.log("bob rewards %d", vault.unlockedRewards(bob));

        // bob resubscribes
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 7, 0,  address(0)));
        weth.approve(address(vault), 1e12);
        vault.depositWeth(bob, 1e12);
        vm.warp(block.timestamp + 190 days);

        vm.startPrank(env.accounts(0));
        altt.transfer(address(vault), 1000e18);

        assertLt(vault.unlockedRewards(bob), vault.unlockedRewards(carol), "final");
    }

   function test_poc() public {
        uint256 amount = 10000e18;

        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);

        // subscribe to alice from carol
        vm.startPrank(carol);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.LIFETIME, 1, amount, address(0)));
        assertEq(registry.getSubDetails(alice, carol), type(uint256).max);
        console.log("total rewards %d", altt.balanceOf(address(vault)) - amount);

        // subscribe to alice from bob
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, amount, address(0)));
        console.log("total rewards %d", altt.balanceOf(address(vault)) - 2*amount);
        vm.warp(block.timestamp + 20 days);

        console.log("day 21 rewards %d", vault.unlockedRewards(bob) + vault.unlockedRewards(carol));


        vm.warp(block.timestamp + 180 days); // bob expired here
        assertLt(vault.unlockedRewards(bob), vault.unlockedRewards(carol));
        console.log("day 201 rewards %d", vault.unlockedRewards(bob) + vault.unlockedRewards(carol));

        // bob resubscribes
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 7, amount, address(0)));
        assertLt(vault.balanceOf(bob), vault.balanceOf(carol));
        vm.warp(block.timestamp + 190 days);

        vm.startPrank(env.accounts(0));
        altt.transfer(address(vault), 1000e18);

        assertLt(vault.unlockedRewards(bob), vault.unlockedRewards(carol));
    }

   function test_hal01() public {
        uint256 amount = 10000e18;

        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);

        // subscribe to alice from carol
        vm.startPrank(carol);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.LIFETIME, 1, amount, address(0)));
        console.log("carol shares %d", vault.balanceOf(carol));

        vm.warp(block.timestamp + 250 days);

        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 2, amount, address(0)));
        console.log("bob shares %d", vault.balanceOf(carol));

        vm.warp(block.timestamp + 30 days);

        // This should revert
        vault.withdraw(amount, bob, bob);

    }


   /// forge-config: default.fuzz.runs = 100
   function testFuzz_redepositSumsBoosted(uint256 x, uint256 y) public {
       x = bound(x, 1e15, 1e21);
       y = bound(y, 1e15, 1e21);
       uint256 snapshot = vm.snapshot();
       tge();
       address alice = env.accounts(1);
       address bob = env.accounts(2);
       address carol = env.accounts(3);

       // subscribe to alice from carol
       vm.startPrank(carol);
       registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.LIFETIME, 1, 1e18, address(0)));
       assertEq(registry.getSubDetails(alice, carol), type(uint256).max);

       // subscribe to alice from bob
       vm.startPrank(bob);
       uint256 bobBefore = altt.balanceOf(bob);
       registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, x, address(0)));

       vm.warp(block.timestamp + 31 days); // bob expired here


       //assertEq(true,false);
       // bob resubscribes
       vm.startPrank(bob);
       registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, y, address(0)));

       vm.warp(block.timestamp + 30 days);
       vm.startPrank(bob);

       uint256 maxWithdraw = vault.maxWithdraw(bob);
       assertGe(maxWithdraw, y);
       vault.withdraw(maxWithdraw, bob, bob);
       uint256 bobRewardsSeparate = altt.balanceOf(bob) - bobBefore;
       console.log("separate rewards %d", bobRewardsSeparate);
       vm.revertTo(snapshot);
       tge();
       vm.startPrank(carol);
       registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.LIFETIME, 1, 1e18, address(0)));
       assertEq(registry.getSubDetails(alice, carol), type(uint256).max);

       // subscribe to alice from bob
       vm.startPrank(bob);
       bobBefore = altt.balanceOf(bob);
       registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 2, x+y, address(0)));

       vm.warp(block.timestamp + 60 days); // bob expired here

       maxWithdraw = vault.maxWithdraw(bob);
       vault.withdraw(maxWithdraw, bob, bob);
       uint256 bobRewardsJoint = altt.balanceOf(bob) - bobBefore;
       assertGt(bobRewardsJoint, bobRewardsSeparate*15/10);
   }


   function testFuzz_stakingBoostApplied(uint256 a) public {
       a = bound(a, 1e18, 10000e18);
       tge();
       address alice = env.accounts(1);
       address bob = env.accounts(2);
       address carol = env.accounts(3);

       uint256 snapshot = vm.snapshot();
       vm.startPrank(bob);
       registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, a, address(0)));
       uint256 dayZeroBob = vault.balanceOf(bob);

       vm.warp(block.timestamp + 20 days);

       vm.startPrank(carol);
       
       registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.MONTHLY, 1, a, address(0)));
       uint256 dayTwentyCarol = vault.balanceOf(carol);

       assertGt(dayZeroBob, dayTwentyCarol);

       vm.startPrank(bob);
       uint256 bobRewards = vault.withdraw(vault.maxWithdraw(bob), bob, bob);
       vm.startPrank(carol);
       uint256 carolRewards = vault.withdraw(vault.maxWithdraw(carol), carol, carol);

       assertGt(bobRewards, carolRewards);
   }


   // function testFuzz_stakingBoostNotLostOnRedeposit(uint256 a) public {
   //     a = bound(a, 1e18, 10000e18);
   //     tge();
   //     address alice = env.accounts(1);
   //     address bob = env.accounts(2);
   //     address carol = env.accounts(3);

   //     uint256 snapshot = vm.snapshot();
   //     vm.startPrank(bob);
   //     uint256 bobBefore = altt.balanceOf(bob);
   //     registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, a, address(0)));
   //     vm.warp(block.timestamp + 20 days); // sub is still active here, boost applies since beginning of sub
   //     altt.approve(address(vault), type(uint256).max);
   //     vault.deposit(a/10, bob);
   //     vm.warp(block.timestamp + 5 days);
   //     uint256 bobAfter = altt.balanceOf(bob);

   //     vm.revertTo(snapshot);
   //     vm.startPrank(carol);
   //     uint256 carolBefore = altt.balanceOf(carol);
   //     registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.MONTHLY, 1, a + a/10, address(0)));
   //     vm.warp(block.timestamp + 25 days);
   //     vault.withdraw(vault.maxWithdraw(carol), carol, carol);
   //     uint256 carolAfter = altt.balanceOf(carol);

   //     assertEq(bobAfter - bobBefore, carolAfter - carolBefore);
   // }

   function testFuzz_boostLostOnLargeWithdraw(uint256 a, uint256 diff) public {
       a = bound(a, 1e18, 10000e18);
       diff = bound(diff, a/200, a/10);
       tge();
       address alice = env.accounts(1);
       address bob = env.accounts(2);
       address carol = env.accounts(3);

       vm.startPrank(bob);
       registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, a, address(0)));
       vm.warp(block.timestamp + 20 days);

       uint256 snapshot = vm.snapshot();

       uint256 safeAmount = vault.unlockedRewards(bob);
       console.log("outside %d", safeAmount);
       vault.withdraw(safeAmount, bob, bob);
       uint256 boostedBalance = vault.balanceOf(bob);
       
       vm.revertTo(snapshot);

       uint256 unsafeAmount = safeAmount + diff;
       vault.withdraw(unsafeAmount, bob, bob);
       uint256 lostBoostBalance = vault.balanceOf(bob);
       
       // ensure that our shares lost much more than the diff we added to the safe withdraw amount
       assertGt(boostedBalance - lostBoostBalance, vault.convertToShares(diff));
   }

   function testFuzz_selfStake(uint256 amount) public {
        amount = bound(amount, 1e18, 100e18);
        uint256 d = 80;
        tge();
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        address carol = env.accounts(3);

        // subscribe to alice
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.LIFETIME, 1, amount, address(0)));
        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, type(uint256).max);

        // stake to alice
        vault = StakingVault(stakingFactory.vaults(alice));
        uint256 shares = vault.balanceOf(bob);
        assertEq(vault.totalSupply(), shares, "a");
        assertEq(vault.getDeposit(bob), amount, "c");

        // alice stakes to self
        vm.startPrank(alice);
        altt.approve(address(vault), amount/2);
        vault.deposit(amount/2, alice);
        // generate yield to vault from carol
        vm.startPrank(carol);
        weth.approve(address(vault), 1e18);
        assertEq(weth.allowance(carol, address(vault)), 1e18);

        // spend 1 eth, swap 12 altt into pool
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        assertGt(vault.totalAssets(), amount);
        console.log("assets inside: %d", vault.totalAssets());
        // alice unstakes
        vm.stopPrank(); vm.startPrank(alice);
        uint256 maxRedeem = vault.maxRedeem(alice);
        assertGt(maxRedeem, 0, "maxredeem");
        assertEq(vault.maxWithdraw(alice), amount/2);
        uint256 received = vault.redeem(maxRedeem, alice, alice);

        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);
        uint256 lifetimePrice = registry.getSubPrice(alice, SubscribeRegistry.packages.LIFETIME);
        // we only get our original stake at the 0th day
        assertApproxEqAbs(received, amount/2, 0.05e18);
        
        vm.startPrank(bob);
        vm.warp(block.timestamp + d*1 days);
        maxRedeem = vault.maxRedeem(bob);
        received = vault.redeem(maxRedeem, bob, bob);

        uint256 target = ((monthlyPrice*1200/10000) + (lifetimePrice*1200/10000));
        target = target*(d*1e18/180)/1e16; // apply vesting
        target = (target*ethusd)/1e8; // convert to ALTT
        assertGt(received, amount);
    }


}
