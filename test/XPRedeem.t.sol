pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "./TestEnv.t.sol";
import "forge-std/console.sol";
import "../src/XPRedeem.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";


contract XPRedeemTest is Test {
    using MessageHashUtils for bytes32;

    TestEnv env;
    XPRedeem redeem;
    uint256 signerKey;
    address signerAddr;

    address alice;
    address bob;
    function setUp() public {
        env = new TestEnv();
        signerKey = 103146436587990934359930128438674959837762129360728181563321989148073222136382;
        signerAddr = vm.addr(signerKey);
        redeem = new XPRedeem(address(env.altt()), signerAddr);
        alice = env.accounts(1);
        bob = env.accounts(2);
    }

    function test_noRedeemBeforeStart() public {
        vm.startPrank(alice);
        vm.expectRevert(bytes("not yet"));
        redeem.redeemXP(1, block.timestamp, bytes("asd"));
    }

    function test_noRedeemWithoutBalance() public {
        vm.startPrank(signerAddr);
        redeem.startRedeem();
        vm.stopPrank();
        vm.warp(block.timestamp + 200);
        // signature is for alice
        bytes32 hash = keccak256(abi.encodePacked(bytes("ALTT_SEP"), env.accounts(1), uint256(100), uint256(8453), block.timestamp - 200)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(sig.length, 65);

        vm.startPrank(alice);
        vm.expectRevert(bytes("BAL"));
        redeem.redeemXP(100, block.timestamp - 200, sig);
    }

    function testFuzz_noRedeemWithInvalidAcc(uint256 a) public {
        a = bound(a, 1, 10);
        vm.startPrank(signerAddr);
        redeem.startRedeem();
        vm.stopPrank();
        vm.warp(block.timestamp + 100 days);
        // signature is for alice
        bytes32 hash = keccak256(abi.encodePacked(bytes("ALTT_SEP"), alice, uint256(100), uint256(8453), block.timestamp - 200)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(sig.length, 65);
        assertEq(env.altt().owner(), env.accounts(0));
        vm.startPrank(env.accounts(0));
        env.altt().mint();
        uint256 balance = env.altt().balanceOf(env.accounts(0));
        console.log("%d", balance);
        env.altt().transfer(address(redeem), balance);
        vm.stopPrank();

        vm.startPrank(bob); // ... but we use bob
        vm.expectRevert(bytes("SIG"));
        redeem.redeemXP(100, block.timestamp - 200, sig);
    }

    function testFuzz_noRedeemWithInvalidAmount(uint256 a) public {
        vm.assume(a != 100 && a < 1e9);
        vm.startPrank(signerAddr);
        redeem.startRedeem();
        vm.stopPrank();
        vm.warp(block.timestamp + 100 days);
        // signature is for alice
        bytes32 hash = keccak256(abi.encodePacked(bytes("ALTT_SEP"), alice, uint256(100), uint256(8453), block.timestamp - 200)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(sig.length, 65);
        assertEq(env.altt().owner(), env.accounts(0));
        vm.startPrank(env.accounts(0));
        env.altt().mint();
        env.altt().transfer(address(redeem), env.altt().balanceOf(env.accounts(0)));
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(bytes("SIG"));
        redeem.redeemXP(a, block.timestamp - 200, sig);
    }

    function testFuzz_noRedeemWithInvalidDeadline(uint256 a) public {
        vm.assume(a != 200);
        vm.startPrank(signerAddr);
        redeem.startRedeem();
        vm.stopPrank();
        vm.warp(block.timestamp + 100 days);
        // signature is for alice
        bytes32 hash = keccak256(abi.encodePacked(bytes("ALTT_SEP"), env.accounts(1), uint256(100), uint256(8453), block.timestamp - 200)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(sig.length, 65);
        assertEq(env.altt().owner(), env.accounts(0));
        vm.startPrank(env.accounts(0));
        env.altt().mint();
        env.altt().transfer(address(redeem), env.altt().balanceOf(env.accounts(0)));
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert();
        redeem.redeemXP(100, block.timestamp - a, sig);
    }

    function test_noEarlyRedeem() public {
        vm.startPrank(signerAddr);
        redeem.startRedeem();
        vm.stopPrank();
        vm.warp(block.timestamp + 100 days);
        // signature is for alice
        bytes32 hash = keccak256(abi.encodePacked(bytes("ALTT_SEP"), env.accounts(1), uint256(100), uint256(8453), block.timestamp + 100 minutes)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(sig.length, 65);
        assertEq(env.altt().owner(), env.accounts(0));
        vm.startPrank(env.accounts(0));
        env.altt().mint();
        env.altt().transfer(address(redeem), env.altt().balanceOf(env.accounts(0)));
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(bytes("not yet"));
        redeem.redeemXP(100, block.timestamp + 100 minutes, sig);
    }

    function test_redeemPenalties() public {
        vm.startPrank(env.accounts(0));
        vm.warp(block.timestamp + 100 days);
        assertEq(env.altt().owner(), env.accounts(0));
        env.altt().mint();
        env.altt().transfer(address(redeem), 100e18);
        vm.stopPrank();

        vm.startPrank(signerAddr);
        redeem.startRedeem();
        vm.stopPrank();

        // signature is for alice
        uint256 deadline = block.timestamp;
        bytes32 hash = keccak256(abi.encodePacked(bytes("ALTT_SEP"), env.accounts(1), uint256(100e18), uint256(8453), deadline)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(sig.length, 65);

        console.log("snapshot: %d", deadline);
        uint256 snapshot = vm.snapshot();

        for (uint256 day = 1; day < 365; day++) {
            vm.startPrank(env.accounts(1));
            console.log("before warp %d", block.timestamp);
            vm.warp(deadline + day * 1 days);
            console.log("after warp %d", block.timestamp);
            uint256 before = env.altt().balanceOf(env.accounts(1));
            redeem.redeemXP(100e18, deadline, sig);
            uint256 delta = env.altt().balanceOf(env.accounts(1)) - before;
            console.log("day %d, unlocked %d", day, delta);
            assertGt(delta, 5e18);
            assertTrue(delta <= 100e18);
            vm.revertTo(snapshot);
        }


    }

}
