// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/SmartRouter.sol";
import "../src/TradeManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

// use only on fork
contract TradeManagerTest is Test {
    address public constant ALTT = 0x1B5cE2a593a840E3ad3549a34D7b3dEc697c114D;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    SmartRouter public router;
    TradeManager public manager;
    address public team = makeAddr("team");

    struct BalanceState {
        uint256 aliceBefore;
        uint256 teamBefore;
        uint256 trenchOwnerBefore;
        uint256 ref1Before;
        uint256 ref2Before;
        uint256 ref3Before;
        uint256 ref4Before;

        uint256 aliceAfter;
        uint256 teamAfter;
        uint256 trenchOwnerAfter;
        uint256 ref1After;
        uint256 ref2After;
        uint256 ref3After;
        uint256 ref4After;
    }


    function setUp() public {
        address[] memory tokens = new address[](5);
        tokens[0] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        tokens[1] = 0x4200000000000000000000000000000000000006;
        tokens[2] = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
        tokens[3] = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
        tokens[4] = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
        router = new SmartRouter(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a, tokens);
        manager = new TradeManager(owner, team, 0x2626664c2603336E57B271c5C0b26F421741e481, WETH);
    }

    function test_smartQuote() public {
        (bool success, bytes memory result) = address(router).call(abi.encodeWithSignature("exactInputPath(address,address,uint256)", ALTT, USDC, 100 ether));

        //abi.encodePacked(tokenIn, v3Fees[j], tokens[i], v3Fees[k], tokenOut);
    }

    function testFuzz_createPositionNoRef(uint256 amount) public {
        amount = bound(amount, 1 ether, 10 ether);
        SmartRouter.TradePath memory path = router.exactInputPath(WETH, ALTT, amount);
        address trenchOwner = makeAddr("trenchOwner");
        address[] memory refs = new address[](0);
        TradeManager.CreatePositionParams memory params = TradeManager.CreatePositionParams({
                path: path.path,
                amount: amount,
                quote: path.expectedAmount,
                slippage: 9000,
                trenchOwner: trenchOwner,
                refs: refs
        });

        address alice = makeAddr("alice");
        vm.deal(alice, amount * 2);
        BalanceState memory state = BalanceState({
                aliceBefore: IERC20(ALTT).balanceOf(alice),
                teamBefore: IERC20(WETH).balanceOf(team),
                trenchOwnerBefore: IERC20(WETH).balanceOf(trenchOwner),
                ref1Before: 0,
                ref2Before: 0,
                ref3Before: 0,
                ref4Before: 0,
                aliceAfter: 0,
                teamAfter: 0,
                trenchOwnerAfter: 0,
                ref1After: 0,
                ref2After: 0,
                ref3After: 0,
                ref4After: 0
        });
        vm.startPrank(alice);

        manager.createPosition{value: amount}(params);

        state.aliceAfter = IERC20(ALTT).balanceOf(alice);
        state.teamAfter = IERC20(WETH).balanceOf(team);
        state.trenchOwnerAfter = IERC20(WETH).balanceOf(trenchOwner);

        assertApproxEqRel(state.aliceAfter - state.aliceBefore, path.expectedAmount, 0.05 ether);
        assertApproxEqRel(state.teamAfter - state.teamBefore, amount * 8 / 1000, 0.05 ether);
        assertApproxEqRel(state.trenchOwnerAfter - state.trenchOwnerBefore, amount * 2 / 1000, 0.05 ether);

    }


    function testFuzz_createPositionLevel1Ref(uint256 amount) public {
        amount = bound(amount, 1 ether, 10 ether);
        SmartRouter.TradePath memory path = router.exactInputPath(WETH, ALTT, amount);
        address trenchOwner = makeAddr("trenchOwner");
        address[] memory refs = new address[](1);
        refs[0] = makeAddr("ref1");
        TradeManager.CreatePositionParams memory params = TradeManager.CreatePositionParams({
                path: path.path,
                amount: amount,
                quote: path.expectedAmount,
                slippage: 9000,
                trenchOwner: trenchOwner,
                refs: refs
        });

        address alice = makeAddr("alice");
        vm.deal(alice, amount * 2);


        BalanceState memory state = BalanceState({
            aliceBefore: IERC20(ALTT).balanceOf(alice),
            teamBefore: IERC20(WETH).balanceOf(team),
            trenchOwnerBefore: IERC20(WETH).balanceOf(trenchOwner),
            ref1Before: IERC20(WETH).balanceOf(makeAddr("ref1")),
            ref2Before: 0,
            ref3Before: 0,
            ref4Before: 0,
            aliceAfter: 0,
            teamAfter: 0,
            trenchOwnerAfter: 0,
            ref1After: 0,
            ref2After: 0,
            ref3After: 0,
            ref4After: 0
        });

        vm.startPrank(alice);

        manager.createPosition{value: amount}(params);

        state.aliceAfter = IERC20(ALTT).balanceOf(alice);
        state.teamAfter = IERC20(WETH).balanceOf(team);
        state.trenchOwnerAfter = IERC20(WETH).balanceOf(trenchOwner);


        assertApproxEqRel(state.aliceAfter - state.aliceBefore, path.expectedAmount, 0.01 ether, "alice");
        assertApproxEqRel(state.teamAfter - state.teamBefore, amount * 7 / 1000, 0.05 ether, "team");
        assertApproxEqRel(state.trenchOwnerAfter - state.trenchOwnerBefore, amount * 2 / 1000, 0.05 ether, "ref1");

    }

    function testFuzz_createPositionLevel2Ref(uint256 amount) public {
        amount = bound(amount, 1 ether, 10 ether);
        SmartRouter.TradePath memory path = router.exactInputPath(WETH, ALTT, amount);
        address trenchOwner = makeAddr("trenchOwner");
        address[] memory refs = new address[](2);
        refs[0] = makeAddr("ref1");
        refs[1] = makeAddr("ref2");
        TradeManager.CreatePositionParams memory params = TradeManager.CreatePositionParams({
                path: path.path,
                amount: amount,
                quote: path.expectedAmount,
                slippage: 9000,
                trenchOwner: trenchOwner,
                refs: refs
        });

        address alice = makeAddr("alice");
        vm.deal(alice, amount * 2);


        BalanceState memory state = BalanceState({
            aliceBefore: IERC20(ALTT).balanceOf(alice),
            teamBefore: IERC20(WETH).balanceOf(team),
            trenchOwnerBefore: IERC20(WETH).balanceOf(trenchOwner),
            ref1Before: IERC20(WETH).balanceOf(makeAddr("ref1")),
            ref2Before: IERC20(WETH).balanceOf(makeAddr("ref2")),
            ref3Before: 0,
            ref4Before: 0,
            aliceAfter: 0,
            teamAfter: 0,
            trenchOwnerAfter: 0,
            ref1After: 0,
            ref2After: 0,
            ref3After: 0,
            ref4After: 0
        });

        vm.startPrank(alice);

        manager.createPosition{value: amount}(params);

        state.aliceAfter = IERC20(ALTT).balanceOf(alice);
        state.teamAfter = IERC20(WETH).balanceOf(team);
        state.trenchOwnerAfter = IERC20(WETH).balanceOf(trenchOwner);

        state.ref1After = IERC20(WETH).balanceOf(makeAddr("ref1"));
        state.ref2After = IERC20(WETH).balanceOf(makeAddr("ref2"));

        assertApproxEqRel(state.aliceAfter - state.aliceBefore, path.expectedAmount, 0.01 ether, "alice");
        assertApproxEqAbs(state.teamAfter - state.teamBefore, amount * 64 / 10000, 0.05 ether, "team");
        assertApproxEqAbs(state.trenchOwnerAfter - state.trenchOwnerBefore, amount * 2 / 1000, 0.01 ether, "trench");
        assertApproxEqAbs(state.ref1After - state.ref1Before, amount * 1 / 1000, 0.01 ether, "ref1");
        assertApproxEqAbs(state.ref2After - state.ref2Before, amount * 6 / 10000, 0.01 ether, "ref2");
    }

    function testFuzz_createPositionLevel3Ref(uint256 amount) public {
        amount = bound(amount, 1 ether, 10 ether);
        SmartRouter.TradePath memory path = router.exactInputPath(WETH, ALTT, amount);
        address trenchOwner = makeAddr("trenchOwner");
        address[] memory refs = new address[](3);
        refs[0] = makeAddr("ref1");
        refs[1] = makeAddr("ref2");
        refs[2] = makeAddr("ref3");
        TradeManager.CreatePositionParams memory params = TradeManager.CreatePositionParams({
                path: path.path,
                amount: amount,
                quote: path.expectedAmount,
                slippage: 9000,
                trenchOwner: trenchOwner,
                refs: refs
        });

        address alice = makeAddr("alice");
        vm.deal(alice, amount * 2);


        BalanceState memory state = BalanceState({
            aliceBefore: IERC20(ALTT).balanceOf(alice),
            teamBefore: IERC20(WETH).balanceOf(team),
            trenchOwnerBefore: IERC20(WETH).balanceOf(trenchOwner),
            ref1Before: IERC20(WETH).balanceOf(makeAddr("ref1")),
            ref2Before: IERC20(WETH).balanceOf(makeAddr("ref2")),
            ref3Before: IERC20(WETH).balanceOf(makeAddr("ref3")),
            ref4Before: 0,
            aliceAfter: 0,
            teamAfter: 0,
            trenchOwnerAfter: 0,
            ref1After: 0,
            ref2After: 0,
            ref3After: 0,
            ref4After: 0
        });

        vm.startPrank(alice);

        manager.createPosition{value: amount}(params);

        state.aliceAfter = IERC20(ALTT).balanceOf(alice);
        state.teamAfter = IERC20(WETH).balanceOf(team);
        state.trenchOwnerAfter = IERC20(WETH).balanceOf(trenchOwner);

        state.ref1After = IERC20(WETH).balanceOf(makeAddr("ref1"));
        state.ref2After = IERC20(WETH).balanceOf(makeAddr("ref2"));
        state.ref3After = IERC20(WETH).balanceOf(makeAddr("ref3"));

        assertApproxEqRel(state.aliceAfter - state.aliceBefore, path.expectedAmount, 0.01 ether, "alice");
        assertApproxEqAbs(state.teamAfter - state.teamBefore, amount * 61 / 10000, 0.05 ether, "team");
        assertApproxEqAbs(state.trenchOwnerAfter - state.trenchOwnerBefore, amount * 2 / 1000, 0.01 ether, "trench");
        assertApproxEqAbs(state.ref1After - state.ref1Before, amount * 1 / 1000, 0.01 ether, "ref1");
        assertApproxEqAbs(state.ref2After - state.ref2Before, amount * 6 / 10000, 0.01 ether, "ref2");
        assertApproxEqAbs(state.ref3After - state.ref3Before, amount * 3 / 10000, 0.01 ether, "ref3");
    }

    function testFuzz_createPositionLevel4Ref(uint256 amount) public {
        amount = bound(amount, 1 ether, 10 ether);
        SmartRouter.TradePath memory path = router.exactInputPath(WETH, ALTT, amount);
        address trenchOwner = makeAddr("trenchOwner");
        address[] memory refs = new address[](4);
        refs[0] = makeAddr("ref1");
        refs[1] = makeAddr("ref2");
        refs[2] = makeAddr("ref3");
        refs[3] = makeAddr("ref4");
        TradeManager.CreatePositionParams memory params = TradeManager.CreatePositionParams({
                path: path.path,
                amount: amount,
                quote: path.expectedAmount,
                slippage: 9000,
                trenchOwner: trenchOwner,
                refs: refs
        });

        address alice = makeAddr("alice");
        vm.deal(alice, amount * 2);


        BalanceState memory state = BalanceState({
            aliceBefore: IERC20(ALTT).balanceOf(alice),
            teamBefore: IERC20(WETH).balanceOf(team),
            trenchOwnerBefore: IERC20(WETH).balanceOf(trenchOwner),
            ref1Before: IERC20(WETH).balanceOf(makeAddr("ref1")),
            ref2Before: IERC20(WETH).balanceOf(makeAddr("ref2")),
            ref3Before: IERC20(WETH).balanceOf(makeAddr("ref3")),
            ref4Before: IERC20(WETH).balanceOf(makeAddr("ref4")),
            aliceAfter: 0,
            teamAfter: 0,
            trenchOwnerAfter: 0,
            ref1After: 0,
            ref2After: 0,
            ref3After: 0,
            ref4After: 0
        });

        vm.startPrank(alice);

        manager.createPosition{value: amount}(params);

        state.aliceAfter = IERC20(ALTT).balanceOf(alice);
        state.teamAfter = IERC20(WETH).balanceOf(team);
        state.trenchOwnerAfter = IERC20(WETH).balanceOf(trenchOwner);

        state.ref1After = IERC20(WETH).balanceOf(makeAddr("ref1"));
        state.ref2After = IERC20(WETH).balanceOf(makeAddr("ref2"));
        state.ref3After = IERC20(WETH).balanceOf(makeAddr("ref3"));
        state.ref4After = IERC20(WETH).balanceOf(makeAddr("ref4"));

        assertApproxEqRel(state.aliceAfter - state.aliceBefore, path.expectedAmount, 0.01 ether, "alice");
        assertApproxEqAbs(state.teamAfter - state.teamBefore, amount * 60 / 10000, 10, "team");
        assertApproxEqAbs(state.trenchOwnerAfter - state.trenchOwnerBefore, amount * 2 / 1000, 10, "trench");
        assertApproxEqAbs(state.ref1After - state.ref1Before, amount * 1 / 1000, 10, "ref1");
        assertApproxEqAbs(state.ref2After - state.ref2Before, amount * 6 / 10000, 10, "ref2");
        assertApproxEqAbs(state.ref3After - state.ref3Before, amount * 3 / 10000, 10, "ref3");
        assertApproxEqAbs(state.ref4After - state.ref4Before, amount * 1 / 10000, 10, "ref4");
    }

    function createPosition(uint256 amount) internal returns (uint256) {
        SmartRouter.TradePath memory path = router.exactInputPath(WETH, ALTT, amount);
        address trenchOwner = makeAddr("trenchOwner");
        address[] memory refs = new address[](1);
        refs[0] = makeAddr("ref1");
        TradeManager.CreatePositionParams memory params = TradeManager.CreatePositionParams({
                path: path.path,
                amount: amount,
                quote: path.expectedAmount,
                slippage: 9000,
                trenchOwner: trenchOwner,
                refs: refs
        });

        address alice = makeAddr("alice");
        vm.deal(alice, amount * 2);
        vm.startPrank(alice);
        uint256 ret = manager.createPosition{value: amount}(params);
        vm.stopPrank();
        return ret;
    }

    function testFuzz_closePositionLevel1Ref(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 ether, 10 ether);
        uint256 amountOut = createPosition(amountIn);
        address trenchOwner = makeAddr("trenchOwner");
        address[] memory refs = new address[](1);
        refs[0] = makeAddr("ref1");
        SmartRouter.TradePath memory path = router.exactInputPath(ALTT, WETH, amountOut);
        TradeManager.CreatePositionParams memory params = TradeManager.CreatePositionParams({
                path: path.path,
                amount: amountOut,
                quote: path.expectedAmount,
                slippage: 10000,
                trenchOwner: trenchOwner,
                refs: refs
        });
        vm.startPrank(makeAddr("alice"));
        console.log("%s", IERC20(ALTT).balanceOf(makeAddr("alice")));
        IERC20(ALTT).approve(address(manager), amountOut);
        manager.closePosition(params);
        vm.stopPrank();
    }

    function testFuzz_closePositionExactAmount(uint256 amountIn) public {
        amountIn = bound(amountIn, 1 ether, 10 ether);
        uint256 amountOut = createPosition(amountIn);
        address trenchOwner = makeAddr("trenchOwner");
        address[] memory refs = new address[](1);
        refs[0] = makeAddr("ref1");
        SmartRouter.TradePath memory path = router.exactInputPath(ALTT, WETH, amountOut + 1);
        TradeManager.CreatePositionParams memory params = TradeManager.CreatePositionParams({
                path: path.path,
                amount: amountOut + 1,
                quote: path.expectedAmount,
                slippage: 10000,
                trenchOwner: trenchOwner,
                refs: refs
        });
        vm.startPrank(makeAddr("alice"));
        IERC20(ALTT).approve(address(manager), amountOut+1);
        vm.expectRevert();
        manager.closePosition(params);
        vm.stopPrank();
    }



 }
