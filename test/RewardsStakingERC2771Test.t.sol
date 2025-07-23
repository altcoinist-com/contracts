// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RewardsStaking.sol";
import "./utils/MockERC20.sol";
import "./utils/MockTrustedForwarder.sol";

contract RewardsStakingERC2771Test is Test {
    RewardsStaking public stakingContract;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;
    MockTrustedForwarder public trustedForwarder;

    address public owner;
    address public user1;
    address public user2;
    address public relayer;

    event Staked(address indexed user, uint256 amount, RewardsStaking.LockType lockType, uint256 positionIndex);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        relayer = makeAddr("relayer");

        // Deploy tokens
        stakingToken = new MockERC20("Staking Token", "STK", 18, 1_000_000e18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18, 1_000_000e18);

        // Deploy mock trusted forwarder
        trustedForwarder = new MockTrustedForwarder();

        // Deploy staking contract
        stakingContract = new RewardsStaking(stakingToken, address(trustedForwarder));

        // Setup balances
        stakingToken.transfer(user1, 10_000e18);
        stakingToken.transfer(user2, 10_000e18);

        // Add reward token
        stakingContract.addRewardToken(address(rewardToken));
    }

    function test_TrustedForwarderSetup() public {
        assertTrue(stakingContract.isTrustedForwarder(address(trustedForwarder)));
        assertFalse(stakingContract.isTrustedForwarder(user1));
        assertFalse(stakingContract.isTrustedForwarder(address(0)));

        assertEq(stakingContract.trustedForwarder(), address(trustedForwarder));
        assertEq(stakingContract.owner(), owner);
    }

    function test_SimpleMetaTransaction() public {
        // Setup: user1 approves tokens
        vm.prank(user1);
        stakingToken.approve(address(stakingContract), 1000e18);

        // Prepare meta-transaction data
        bytes memory callData = abi.encodeWithSelector(
            stakingContract.stake.selector,
            100e18,
            RewardsStaking.LockType.LIQUID,
            false
        );

        // Execute meta-transaction using simplified forwarder
        vm.expectEmit(true, true, true, true);
        emit Staked(user1, 100e18, RewardsStaking.LockType.LIQUID, 0);
        
        vm.prank(relayer);
        trustedForwarder.executeAs(user1, address(stakingContract), callData);

        // Verify position was created for user1
        RewardsStaking.StakingPosition memory position = stakingContract.getUserPosition(user1, 0);
        assertEq(position.amount, 100e18);
        assertEq(uint8(position.lockType), uint8(RewardsStaking.LockType.LIQUID));
    }

    function test_MetaTransactionPreservesUserContext() public {
        // Setup two users
        vm.prank(user1);
        stakingToken.approve(address(stakingContract), 1000e18);
        
        vm.prank(user2);
        stakingToken.approve(address(stakingContract), 1000e18);

        // User1 stakes via meta-transaction
        bytes memory callData1 = abi.encodeWithSelector(
            stakingContract.stake.selector,
            100e18,
            RewardsStaking.LockType.LIQUID,
            false
        );

        vm.prank(relayer);
        trustedForwarder.executeAs(user1, address(stakingContract), callData1);

        // User2 stakes via meta-transaction
        bytes memory callData2 = abi.encodeWithSelector(
            stakingContract.stake.selector,
            200e18,
            RewardsStaking.LockType.LOCK_1M,
            false
        );

        vm.prank(relayer);
        trustedForwarder.executeAs(user2, address(stakingContract), callData2);

        // Verify positions are correctly attributed
        RewardsStaking.StakingPosition memory pos1 = stakingContract.getUserPosition(user1, 0);
        RewardsStaking.StakingPosition memory pos2 = stakingContract.getUserPosition(user2, 0);

        assertEq(pos1.amount, 100e18);
        assertEq(pos2.amount, 200e18);
        
        // Verify position counts
        assertEq(stakingContract.getUserPositionCount(user1), 1);
        assertEq(stakingContract.getUserPositionCount(user2), 1);
        assertEq(stakingContract.getUserPositionCount(relayer), 0); // Relayer should have no positions
    }

    function test_DirectCallStillWorks() public {
        // Ensure direct calls still work alongside meta-transactions
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 1000e18);
        
        stakingContract.stake(100e18, RewardsStaking.LockType.LIQUID, false);
        vm.stopPrank();

        // Verify position
        RewardsStaking.StakingPosition memory position = stakingContract.getUserPosition(user1, 0);
        assertEq(position.amount, 100e18);
    }
}