pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "./TestEnv.t.sol";
import "forge-std/console.sol";
import "../src/SubscribeRegistry.sol";
import "../src/StakingFactory.sol";

contract SubscribeRegistryTest is Test {
    TestEnv env;
    SubscribeRegistry registry;
    StakingFactory stakingFactory;
    CreatorTokenFactory creatorFactory;
    IERC20 weth;
    address alice; address bob;
    address team = 0xA6c0CCb2ba30F94b490d5b20d75d1f5330a6d2a3;
    function setUp() public {
        env = new TestEnv();
        registry = env.registry();
        stakingFactory = env.stakingFactory();
        creatorFactory = env.creatorFactory();
        weth = env.weth();
        alice = env.accounts(1);
        bob = env.accounts(2);
        test_noInitialExpiry();
    }

    function initPrice(uint256 m, uint256 l) internal {
        vm.startPrank(alice);
        registry.setSubPrice(m, l, "Jsmith");
        assertTrue(stakingFactory.vaults(alice) != address(0), "uninitialized vault");
        vm.stopPrank();
    }

    function test_noInitialExpiry() public {
        assertEq(registry.getSubDetails(alice, bob), 0);
    }

    function test_cantSubWithoutPool() public {
        vm.startPrank(bob);
        vm.expectRevert(bytes("UV"));
        registry.subscribe(SubscribeRegistry.SubscribeParams(
                                   alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0))
                           );
    }

    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_subscribeMonthly(uint256 m) public {
        m = bound(m, 1e6+1, 1e18);
        initPrice(m, 30e18);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(bob);
        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        assertApproxEqAbs(monthlyPrice, m, 0.001e18);

        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 poolBefore = weth.balanceOf(address(vault));
        uint256 teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(
                                   alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)
                           ));

        uint256 aliceAfter = weth.balanceOf(alice);
        uint256 poolAfter = weth.balanceOf(address(vault));
        uint256 teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(aliceAfter - aliceBefore, (m*80)/100, 0.001e18); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (m*12)/100, 0.001e18); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (m*8)/100, 0.001e18); // 8%
                                                     //
        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days);
    }


    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_subscribeLifetime(uint256 l) public {
        l = bound(l, 12e18, 30e18);
        initPrice(1e18, l);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(bob);
        uint256 lifetimePrice = registry.getSubPrice(alice, SubscribeRegistry.packages.LIFETIME);

        assertApproxEqAbs(lifetimePrice, l, 0.001e18, "price error");

        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 poolBefore = weth.balanceOf(address(vault));
        uint256 teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(
                                   alice, bob, SubscribeRegistry.packages.LIFETIME, 1, 0, address(0)
                           ));

        uint256 aliceAfter = weth.balanceOf(alice);
        uint256 poolAfter = weth.balanceOf(address(vault));
        uint256 teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(aliceAfter - aliceBefore, (l*80)/100, 0.001e18); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (l*12)/100, 0.001e18); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (l*8)/100, 0.001e18); // 8%
                                                     //
        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, type(uint256).max);
    }

    function test_subscribeInvalid() public {
        initPrice(1e18, 5e18);
        vm.startPrank(bob);
        bytes memory subCall = abi.encodeWithSignature("subscribe(address,uint)", alice, 6);
        (bool success, ) = address(registry).call(subCall);
        assertTrue(!success);

    }

    /// forge-config: default.fuzz.runs = 100
    function testFuzz_SubscribeWithReferral(uint256 m) public {
        m = bound(m, 1e6 + 1, 1e18);
        initPrice(m, 30e18);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));


        address carol = env.accounts(3);
        vm.startPrank(carol);
        registry.subscribe(SubscribeRegistry.SubscribeParams(
                                   alice, carol, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)
                           ));
        vm.stopPrank();

        uint256 carolBefore = weth.balanceOf(carol);

        // bob subscribes with carols address as referer
        vm.startPrank(bob);
        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        assertApproxEqAbs(monthlyPrice, m, 0.001e18);

        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 poolBefore = weth.balanceOf(address(vault));
        uint256 teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, carol
                                                            ));

        uint256 aliceDelta = weth.balanceOf(alice) - aliceBefore;
        uint256 poolDelta = weth.balanceOf(address(vault)) - poolBefore;
        uint256 teamDelta = weth.balanceOf(team) - teamBefore;
        uint256 carolDelta = weth.balanceOf(carol) - carolBefore;

        assertApproxEqAbs(carolDelta, (m*8)/100, 0.001e18);
        assertApproxEqAbs(aliceDelta, (m*72)/100, 0.001e18); // 80%
        assertApproxEqAbs(poolDelta, (m*12)/100, 0.001e18); // 12%
        assertApproxEqAbs(teamDelta, (m*8)/100, 0.001e18); // 8%

        assertApproxEqAbs(carolDelta+aliceDelta+poolDelta+teamDelta, monthlyPrice, 0.001e18);

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days);
    }

    function testFuzz_subscribeMultipleMonths(uint256 m) public {
        m = bound(m, 1, 100);
        initPrice(1e18, 30e18);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(bob);
        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        assertApproxEqAbs(monthlyPrice, 1e18, 0.001e18);

        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 poolBefore = weth.balanceOf(address(vault));
        uint256 teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(
                                   alice, bob, SubscribeRegistry.packages.MONTHLY, m, 0, address(0)
                        ));

        uint256 aliceAfter = weth.balanceOf(alice);
        uint256 poolAfter = weth.balanceOf(address(vault));
        uint256 teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(aliceAfter - aliceBefore, (monthlyPrice*m*80)/100, 0.001e18, "author"); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (monthlyPrice*m*12)/100, 0.001e18, "pool"); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (monthlyPrice*m*8)/100, 0.001e18, "team"); // 8%

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + ( m * 30 days));
    }

    function test_addSubscriptionMonths() public {
        initPrice(1e18, 30e18);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(bob);
        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        assertApproxEqAbs(monthlyPrice, 1e18, 0.001e18);

        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 poolBefore = weth.balanceOf(address(vault));
        uint256 teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(
                                   alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)
                        ));

        uint256 aliceAfter = weth.balanceOf(alice);
        uint256 poolAfter = weth.balanceOf(address(vault));
        uint256 teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(aliceAfter - aliceBefore, (monthlyPrice*80)/100, 0.001e18, "author"); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (monthlyPrice*12)/100, 0.001e18, "pool"); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (monthlyPrice*8)/100, 0.001e18, "team"); // 8%

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days);

        for(uint256 i=1; i<20; i++) {
            aliceBefore = weth.balanceOf(alice);
            poolBefore = weth.balanceOf(address(vault));
            teamBefore = weth.balanceOf(team);
            vm.warp(block.timestamp + 1 days);
            registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)
                                                                ));
            aliceAfter = weth.balanceOf(alice);
            poolAfter = weth.balanceOf(address(vault));
            teamAfter = weth.balanceOf(team);

            assertApproxEqAbs(aliceAfter - aliceBefore, (monthlyPrice*80)/100, 0.001e18, "author"); // 80%
            assertApproxEqAbs(poolAfter - poolBefore, (monthlyPrice*12)/100, 0.001e18, "pool"); // 12%
            assertApproxEqAbs(teamAfter - teamBefore, (monthlyPrice*8)/100, 0.001e18, "team"); // 8%

            expiry = registry.getSubDetails(alice, bob);
            assertEq(expiry, block.timestamp + ((i+1)*29 days) + 1 days);
        }
    }

    function test_upgradeSubscription() public {
        initPrice(1e18, 30e18);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(bob);
        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        assertApproxEqAbs(monthlyPrice, 1e18, 0.001e18);

        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 poolBefore = weth.balanceOf(address(vault));
        uint256 teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)
                                                            ));

        uint256 aliceAfter = weth.balanceOf(alice);
        uint256 poolAfter = weth.balanceOf(address(vault));
        uint256 teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(aliceAfter - aliceBefore, (monthlyPrice*80)/100, 0.001e18, "author"); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (monthlyPrice*12)/100, 0.001e18, "pool"); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (monthlyPrice*8)/100, 0.001e18, "team"); // 8%

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days);

        uint256 lifetimePrice = registry.getSubPrice(alice, SubscribeRegistry.packages.LIFETIME);

        aliceBefore = weth.balanceOf(alice);
        poolBefore = weth.balanceOf(address(vault));
        teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.LIFETIME, 1, 0, address(0)
                                                            ));

        aliceAfter = weth.balanceOf(alice);
        poolAfter = weth.balanceOf(address(vault));
        teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(aliceAfter - aliceBefore, (lifetimePrice*80)/100, 0.001e18, "author"); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (lifetimePrice*12)/100, 0.001e18, "pool"); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (lifetimePrice*8)/100, 0.001e18, "team"); // 8%

        expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, type(uint256).max);
    }

    function test_buyStakingRightSeparateActiveSub() public {
        initPrice(1e18, 30e18);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(bob);
        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        assertApproxEqAbs(monthlyPrice, 1e18, 0.001e18);

        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 poolBefore = weth.balanceOf(address(vault));
        uint256 teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));

        uint256 aliceAfter = weth.balanceOf(alice);
        uint256 poolAfter = weth.balanceOf(address(vault));
        uint256 teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(aliceAfter - aliceBefore, (monthlyPrice*80)/100, 0.001e18, "author"); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (monthlyPrice*12)/100, 0.001e18, "pool"); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (monthlyPrice*8)/100, 0.001e18, "team"); // 8%

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days);
        assertEq(creatorFactory.balanceOf(bob, uint256(uint160(alice))), 1);

        aliceBefore = weth.balanceOf(alice);
        poolBefore = weth.balanceOf(address(vault));
        teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));

        aliceAfter = weth.balanceOf(alice);
        poolAfter = weth.balanceOf(address(vault));
        teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(aliceAfter - aliceBefore, (monthlyPrice*80)/100, 0.001e18, "author"); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (monthlyPrice*12)/100, 0.001e18, "pool"); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (monthlyPrice*8)/100, 0.001e18, "team"); // 8%

        expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 60 days);
        assertEq(creatorFactory.balanceOf(bob, uint256(uint160(alice))), 1);
    }

    function test_buyStakingRightSeparateInactiveSub() public {
        initPrice(1e18, 30e18);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));
        vm.startPrank(bob);
        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        assertApproxEqAbs(monthlyPrice, 1e18, 0.001e18);
        assertEq(creatorFactory.balanceOf(bob, uint256(uint160(alice))), 0);

        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 bobBefore = weth.balanceOf(bob);
        uint256 poolBefore = weth.balanceOf(address(vault));
        uint256 teamBefore = weth.balanceOf(team);

        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));

        uint256 aliceAfter = weth.balanceOf(alice);
        uint256 bobAfter = weth.balanceOf(bob);
        uint256 poolAfter = weth.balanceOf(address(vault));
        uint256 teamAfter = weth.balanceOf(team);

        assertApproxEqAbs(bobBefore - bobAfter, monthlyPrice, 0.0001e18);
        assertApproxEqAbs(aliceAfter - aliceBefore, (monthlyPrice*80)/100, 0.001e18, "author"); // 80%
        assertApproxEqAbs(poolAfter - poolBefore, (monthlyPrice*12)/100, 0.001e18, "pool"); // 12%
        assertApproxEqAbs(teamAfter - teamBefore, (monthlyPrice*8)/100, 0.001e18, "team"); // 8%

        uint256 expiry = registry.getSubDetails(alice, bob);
        assertEq(expiry, block.timestamp + 30 days);
        assertEq(creatorFactory.balanceOf(bob, uint256(uint160(alice))), 1);
    }

    function test_creatorCanChangePrice() public {
        initPrice(1e18, 30e18);
        StakingVault vault = StakingVault(stakingFactory.vaults(alice));
        address carol = env.accounts(3);
        vm.startPrank(bob);
        uint256 monthlyPrice = registry.getSubPrice(alice, SubscribeRegistry.packages.MONTHLY);

        assertApproxEqAbs(monthlyPrice, 1e18, 0.001e18);
        assertEq(creatorFactory.balanceOf(bob, uint256(uint160(alice))), 0);
        uint256 bobBefore = weth.balanceOf(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        uint256 bobAfter = weth.balanceOf(bob);

        // alice changes price
        vm.startPrank(alice);
        registry.setSubPrice(2e18, 60e18, "Jsmith");

        vm.startPrank(carol);
        uint256 carolBefore = weth.balanceOf(carol);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, carol, SubscribeRegistry.packages.MONTHLY, 1, 0, address(0)));
        uint256 carolAfter = weth.balanceOf(carol);

        assertEq(carolBefore - carolAfter, 2*(bobBefore - bobAfter));
    }

    function test_resubscribeAfterUnsub() public {
            // TODO
    }
}
