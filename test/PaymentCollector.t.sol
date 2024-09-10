// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "./TestEnv.t.sol";
import {PaymentCollector} from "../src/PaymentCollector.sol"; 
import "../src/StakingVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICSMFactory {
     function createAccount(bytes[] calldata owners, uint256 nonce)
        external
         payable
        virtual
        returns (address);
}

interface CSM {
     function execute(address target, uint256 value, bytes calldata data)
        external
        payable;
    error Initialized();
    error SelectorNotAllowed(bytes4 selector);
    error InvalidNonceKey(uint256 key);
}
contract PaymentCollectorTest is Test {
    ICSMFactory factory = ICSMFactory(0x0BA5ED0c6AA8c49038F819E587E2633c4A9F428a);
    PaymentCollector public paymentCollector;
    TestEnv env;
    StakingVault vault;
    CSM aliceCSM;
    CSM bobCSM;
    IERC20 weth;
    function setUp() public {
        env = new TestEnv();
        paymentCollector = new PaymentCollector(
            env.accounts(0),
            address(env.altt()),
            address(env.registry())
        );
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        vm.startPrank(alice);
        // create CSM wallet for alice & bob
        bytes[] memory owners = new bytes[](1);
        owners[0] = abi.encode(alice);
        //owners[1] = abi.encode(address(paymentCollector));
        aliceCSM = CSM(factory.createAccount(owners, 0));
        vm.startPrank(bob);
        owners[0] = abi.encode(bob);
        bobCSM = CSM(factory.createAccount(owners, 0));

        assertTrue(address(aliceCSM) != address(0));
        assertTrue(address(bobCSM) != address(0));
        vm.startPrank(alice);
        bytes memory cd = abi.encodeWithSignature("setSubPrice(uint256,uint256,string)", 1e18, 5e18, "JSmith");
        aliceCSM.execute(address(env.registry()), 0, cd);
        address vaultAddr = env.stakingFactory().vaults(address(aliceCSM));
        assertTrue(vaultAddr != address(0), "uninitialized vault");
        vault = StakingVault(vaultAddr);
        assertEq(vault.name(), "JSmith ALTT staking pool");

        vm.startPrank(bob);
        env.weth().transfer(address(bobCSM), 1e18);
        cd = abi.encodeWithSignature("approve(address,uint256)", address(env.registry()), type(uint256).max);
        bobCSM.execute(address(env.weth()), 0, cd);
        SubscribeRegistry.SubscribeParams memory params = SubscribeRegistry.SubscribeParams(
            address(aliceCSM),
            address(bobCSM),
            SubscribeRegistry.packages.MONTHLY,
            1,
            0,
            address(0)
        );
        cd = abi.encodeWithSignature("subscribe((address,address,uint8,uint256,uint256,address))",
                                     params);
        bobCSM.execute(address(env.registry()),0,cd);
        uint256 expiry = env.registry().getSubDetails(address(aliceCSM), address(bobCSM));
        assertEq(expiry, block.timestamp + 30 days);
        weth = env.weth();
    }

    function test_canPullAuthorizedRenewal() public {
        // bob authorizes altcoinst to pull payments
        assertGt(env.registry().getRenewPrice(address(aliceCSM), address(bobCSM)), 0);
        // bob tops up his CSM
        weth.transfer(address(bobCSM), 1e18);
        assertEq(weth.balanceOf(address(bobCSM)), 1e18);
        assertGe(weth.allowance(address(bobCSM), address(env.registry())), 1e18);
        bytes memory cd = abi.encodeWithSignature("approve(address,uint256)", address(paymentCollector), type(uint256).max);
        bobCSM.execute(address(env.weth()), 0, cd);
        // altcoinist team pulls payment from bob's CSM
        vm.startPrank(env.accounts(0));
        uint256 monthlyPrice = env.registry().getSubPrice(address(aliceCSM), SubscribeRegistry.packages.MONTHLY);

        uint256 balanceBefore = weth.balanceOf(address(bobCSM));
        uint256 authorBefore = weth.balanceOf(address(aliceCSM));
        uint256 thres = paymentCollector.dateThreshold();
        vm.warp(env.registry().getSubDetails(address(aliceCSM), address(bobCSM)) - thres + 1 minutes);
        paymentCollector.pull(address(bobCSM), address(aliceCSM));
        uint256 balanceAfter = weth.balanceOf(address(bobCSM));
        uint256 authorAfter = weth.balanceOf(address(aliceCSM));

        assertEq(authorAfter - authorBefore, (monthlyPrice*80)/100);
        assertEq(balanceBefore - balanceAfter, monthlyPrice);
    }

    function test_canPullAuthorizedRenewalPriceChanged() public {
        // bob authorizes altcoinst to pull payments
        assertGt(env.registry().getRenewPrice(address(aliceCSM), address(bobCSM)), 0);
        // bob tops up his CSM
        weth.transfer(address(bobCSM), 1e18);
        assertEq(weth.balanceOf(address(bobCSM)), 1e18);
        assertGe(weth.allowance(address(bobCSM), address(env.registry())), 1e18);
        bytes memory cd = abi.encodeWithSignature("approve(address,uint256)", address(paymentCollector), type(uint256).max);
        bobCSM.execute(address(env.weth()), 0, cd);

        // alice doubles price
        vm.startPrank(env.accounts(1));
        cd = abi.encodeWithSignature("setSubPrice(uint256,uint256,string)", 2e18, 10e18, "JSmith");
        aliceCSM.execute(address(env.registry()), 0, cd);

        // altcoinist team pulls payment from bob's CSM
        vm.startPrank(env.accounts(0));
        uint256 monthlyPrice = env.registry().getSubPrice(address(aliceCSM), SubscribeRegistry.packages.MONTHLY);

        uint256 balanceBefore = weth.balanceOf(address(bobCSM));
        uint256 authorBefore = weth.balanceOf(address(aliceCSM));
        uint256 thres = paymentCollector.dateThreshold();
        vm.warp(env.registry().getSubDetails(address(aliceCSM), address(bobCSM)) - thres + 1 minutes);
        paymentCollector.pull(address(bobCSM), address(aliceCSM));
        uint256 balanceAfter = weth.balanceOf(address(bobCSM));
        uint256 authorAfter = weth.balanceOf(address(aliceCSM));

        assertEq(authorAfter - authorBefore, (monthlyPrice*40)/100);
        assertEq(balanceBefore - balanceAfter, monthlyPrice/2);
    }

    function test_cannotPullUnauthorizedRenewal() public {
        // bob authorizes altcoinst to pull payments
        assertGt(env.registry().getRenewPrice(address(aliceCSM), address(bobCSM)), 0);
        // bob tops up his CSM
        weth.transfer(address(bobCSM), 1e18);
        assertEq(weth.balanceOf(address(bobCSM)), 1e18);
        assertGe(weth.allowance(address(bobCSM), address(env.registry())), 1e18);
        // altcoinist team pulls payment from bob's CSM
        vm.startPrank(env.accounts(0));
        uint256 monthlyPrice = env.registry().getSubPrice(address(aliceCSM), SubscribeRegistry.packages.MONTHLY);

        uint256 balanceBefore = weth.balanceOf(address(bobCSM));
        uint256 authorBefore = weth.balanceOf(address(aliceCSM));
        uint256 thres = paymentCollector.dateThreshold();
        vm.warp(env.registry().getSubDetails(address(aliceCSM), address(bobCSM)) - thres + 1 minutes);
        vm.expectRevert();
        paymentCollector.pull(address(bobCSM), address(aliceCSM));
    }

    function test_unusableAfterDeprecation() public {
        // bob authorizes altcoinst to pull payments
        assertGt(env.registry().getRenewPrice(address(aliceCSM), address(bobCSM)), 0);
        // bob tops up his CSM
        weth.transfer(address(bobCSM), 1e18);
        assertEq(weth.balanceOf(address(bobCSM)), 1e18);
        assertGe(weth.allowance(address(bobCSM), address(env.registry())), 1e18);
        bytes memory cd = abi.encodeWithSignature("approve(address,uint256)", address(paymentCollector), type(uint256).max);
        bobCSM.execute(address(env.weth()), 0, cd);

        vm.startPrank(env.accounts(0));
        // altcoinist team deprecates the collector

        paymentCollector.deprecate();

        // altcoinist team pulls payment from bob's CSM
        uint256 monthlyPrice = env.registry().getSubPrice(address(aliceCSM), SubscribeRegistry.packages.MONTHLY);

        uint256 balanceBefore = weth.balanceOf(address(bobCSM));
        uint256 authorBefore = weth.balanceOf(address(aliceCSM));
        uint256 thres = paymentCollector.dateThreshold();
        vm.warp(env.registry().getSubDetails(address(aliceCSM), address(bobCSM)) - thres + 1 minutes);
        vm.expectRevert(bytes("locked"));
        paymentCollector.pull(address(bobCSM), address(aliceCSM));

    }
}
