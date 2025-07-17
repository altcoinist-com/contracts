// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RewardsStaking} from "../src/RewardsStaking.sol";
import {MockERC20} from "../test/utils/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RewardsStakingTest is Test {
    RewardsStaking public staking;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    uint256 public constant INITIAL_TOKEN_BALANCE = 1_000_000 * 10**18;
    uint256 public constant INITIAL_USER_BALANCE = 10_000 * 10**18;
    uint256 public constant MIN_STAKING_AMOUNT = 100 * 10**18;
    
    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        // Deploy tokens
        stakingToken = new MockERC20("Staking Token", "STAKE", 18, INITIAL_TOKEN_BALANCE);
        rewardToken1 = new MockERC20("Reward Token 1", "REW1", 18, INITIAL_TOKEN_BALANCE);
        rewardToken2 = new MockERC20("Reward Token 2", "REW2", 18, INITIAL_TOKEN_BALANCE);
        
        // Deploy staking contract
        staking = new RewardsStaking(stakingToken);
        
        // // Add reward tokens
        // staking.addRewardToken(address(rewardToken1));
        // staking.addRewardToken(address(rewardToken2));
        
        // // Transfer tokens to users
        stakingToken.transfer(user1, 10_000 * 10**18);
        stakingToken.transfer(user2, 10_000 * 10**18);
        stakingToken.transfer(user3, 10_000 * 10**18);
        
        // // Approve users
        // vm.prank(user1);
        // stakingToken.approve(address(staking), type(uint256).max);
        // vm.prank(user2);
        // stakingToken.approve(address(staking), type(uint256).max);
        // vm.prank(user3);
        // stakingToken.approve(address(staking), type(uint256).max);
        
        // // Approve reward tokens
        // rewardToken1.approve(address(staking), type(uint256).max);
        // rewardToken2.approve(address(staking), type(uint256).max);
    }
    
    function test_Constructor() public {
        assertEq(address(staking.stakingToken()), address(stakingToken));
        assertEq(staking.owner(), owner);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.getRewardTokensLength(), 0);
    }
    
    function test_AddRewardToken() public {
        staking.addRewardToken(address(rewardToken1));
        
        assertEq(staking.getRewardTokensLength(), 1);

        assertEq(staking.rewardTokens(0), address(rewardToken1));
        
        assertTrue(staking.isRewardToken(address(rewardToken1)));
        
        assertEq(staking.rewardTokenIndex(address(rewardToken1)), 0);
    }

    function test_AddTwoRewardTokens() public {
        staking.addRewardToken(address(rewardToken1));
        staking.addRewardToken(address(rewardToken2));
        
        assertEq(staking.getRewardTokensLength(), 2);
        
        assertEq(staking.rewardTokens(0), address(rewardToken1));
        assertEq(staking.rewardTokens(1), address(rewardToken2));
        
        assertTrue(staking.isRewardToken(address(rewardToken1)));
        assertTrue(staking.isRewardToken(address(rewardToken2)));
        
        assertEq(staking.rewardTokenIndex(address(rewardToken1)), 0);
        assertEq(staking.rewardTokenIndex(address(rewardToken2)), 1);
    }
    
    function test_AddRewardToken_RevertIfZeroAddress() public {
        vm.expectRevert(RewardsStaking.ZeroAddress.selector);
        staking.addRewardToken(address(0));
    }
    
    function test_AddRewardToken_RevertIfAlreadyAdded() public {
        staking.addRewardToken(address(rewardToken1));

        vm.expectRevert(RewardsStaking.AlreadyAddedRewardToken.selector);
        staking.addRewardToken(address(rewardToken1));
    }

    function test_RemoveRewardToken_FromTheMiddle() public {
        staking.addRewardToken(address(rewardToken1));
        staking.addRewardToken(address(rewardToken2));
        MockERC20 rewardToken3 = new MockERC20("Reward Token 3", "REW3", 18, INITIAL_TOKEN_BALANCE);
        staking.addRewardToken(address(rewardToken3));

        staking.removeRewardToken(address(rewardToken2));
        
        assertEq(staking.getRewardTokensLength(), 2);

        assertEq(staking.rewardTokens(0), address(rewardToken1));
        assertEq(staking.rewardTokens(1), address(rewardToken3));

        assertTrue(staking.isRewardToken(address(rewardToken1)));
        assertFalse(staking.isRewardToken(address(rewardToken2)));
        assertTrue(staking.isRewardToken(address(rewardToken3)));
        
        assertEq(staking.rewardTokenIndex(address(rewardToken1)), 0);
        assertEq(staking.rewardTokenIndex(address(rewardToken2)), 0);
        assertEq(staking.rewardTokenIndex(address(rewardToken3)), 1);
    }
    
    function test_RemoveRewardToken_LastAdded() public {
        staking.addRewardToken(address(rewardToken1));
        staking.addRewardToken(address(rewardToken2));

        staking.removeRewardToken(address(rewardToken2));
        
        assertEq(staking.getRewardTokensLength(), 1);

        assertEq(staking.rewardTokens(0), address(rewardToken1));

        assertTrue(staking.isRewardToken(address(rewardToken1)));
        assertFalse(staking.isRewardToken(address(rewardToken2)));
        
        assertEq(staking.rewardTokenIndex(address(rewardToken1)), 0);
        assertEq(staking.rewardTokenIndex(address(rewardToken2)), 0);
    }
    
    function test_RemoveRewardToken_RevertIfNotAdded() public {
        vm.expectRevert(RewardsStaking.InvalidRewardToken.selector);
        staking.removeRewardToken(address(rewardToken1));
    }

    function test_Stake_RevertIfTooSmall() public {
        uint256 amount = MIN_STAKING_AMOUNT - 1;
        
        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        vm.expectRevert(RewardsStaking.InvalidAmount.selector);
        staking.stake(amount, RewardsStaking.LockType.LIQUID);
        vm.stopPrank();
    }
    
    function test_Stake_Liquid() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LIQUID);
        vm.stopPrank();
        
        // test position
        assertEq(staking.getUserPositionCount(user1), 1);
        RewardsStaking.StakingPosition memory position = staking.getUserPosition(user1, 0);
        assertEq(position.amount, amount);
        assertEq(uint(position.lockType), uint(RewardsStaking.LockType.LIQUID));
        assertEq(position.cooldownStartDaySinceDeployment, 0);
        uint256 deploymentDay = staking.deploymentDay();
        uint256 startDay = deploymentDay + 1;
        assertEq(position.startDaySinceDeployment, startDay);
        assertEq(position.unlockDaySinceDeployment, type(uint32).max);

        assertEq(staking.totalStaked(), amount);
        assertEq(stakingToken.balanceOf(user1), INITIAL_USER_BALANCE - amount);

        // test weight delta 1000 * 10**18 * 500 / 1000
        assertEq(staking.userWeightDelta(user1, startDay), 500 * 10**18);
        assertEq(staking.totalWeightDelta(startDay), 500 * 10**18);
    }
    
    function test_Stake_Locked() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LOCK_3M);
        vm.stopPrank();
        
        uint256 deploymentDay = staking.deploymentDay();
        uint256 startDay = deploymentDay + 1;
        
        RewardsStaking.StakingPosition memory position = staking.getUserPosition(user1, 0);
        assertEq(position.amount, amount);
        assertEq(uint(position.lockType), uint(RewardsStaking.LockType.LOCK_3M));
        assertGt(position.unlockDaySinceDeployment, position.startDaySinceDeployment);
        assertEq(position.cooldownStartDaySinceDeployment, 0);
        assertEq(position.startDaySinceDeployment, startDay);
        assertEq(position.unlockDaySinceDeployment, startDay + 90);

        assertEq(staking.totalStaked(), amount);
        assertEq(stakingToken.balanceOf(user1), INITIAL_USER_BALANCE - amount);

        assertEq(staking.userWeightDelta(user1, deploymentDay), 0);
        assertEq(staking.totalWeightDelta(deploymentDay), 0);

        // test weight delta 1000 * 10**18 * 625 / 1000
        assertEq(staking.userWeightDelta(user1, startDay), 625 * 10**18);
        assertEq(staking.totalWeightDelta(startDay), 625 * 10**18);

        assertEq(staking.userWeightDelta(user1, startDay + 90), -625 * 10**18);
        assertEq(staking.totalWeightDelta(startDay + 90), -625 * 10**18);
    }

    function test_Stake_MultiplePositionsPerUser() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        // User creates multiple positions
        vm.startPrank(user1);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LIQUID);
        
        stakingToken.approve(address(staking), stakeAmount * 2);
        staking.stake(stakeAmount * 2, RewardsStaking.LockType.LOCK_3M);
        
        stakingToken.approve(address(staking), stakeAmount / 2);
        staking.stake(stakeAmount / 2, RewardsStaking.LockType.LOCK_1M);
        vm.stopPrank();
        
        assertEq(staking.getUserPositionCount(user1), 3);
        
        // Check each position
        RewardsStaking.StakingPosition memory pos0 = staking.getUserPosition(user1, 0);
        RewardsStaking.StakingPosition memory pos1 = staking.getUserPosition(user1, 1);
        RewardsStaking.StakingPosition memory pos2 = staking.getUserPosition(user1, 2);
        
        assertEq(pos0.amount, stakeAmount);
        uint256 deploymentDay = staking.deploymentDay();
        uint256 startDay = deploymentDay + 1;
        
        assertEq(uint(pos0.lockType), uint(RewardsStaking.LockType.LIQUID));
        assertEq(pos0.startDaySinceDeployment, startDay);
        assertEq(pos0.unlockDaySinceDeployment, type(uint32).max);
        assertEq(pos0.cooldownStartDaySinceDeployment, 0);
        
        assertEq(pos1.amount, stakeAmount * 2);
        assertEq(uint(pos1.lockType), uint(RewardsStaking.LockType.LOCK_3M));
        assertEq(pos1.startDaySinceDeployment, startDay);
        assertEq(pos1.unlockDaySinceDeployment, startDay + 90);
        assertEq(pos1.cooldownStartDaySinceDeployment, 0);
        
        assertEq(pos2.amount, stakeAmount / 2);
        assertEq(uint(pos2.lockType), uint(RewardsStaking.LockType.LOCK_1M));
        assertEq(pos2.startDaySinceDeployment, startDay);
        assertEq(pos2.unlockDaySinceDeployment, startDay + 30);
        assertEq(pos2.cooldownStartDaySinceDeployment, 0);

        uint256 totalStaked = stakeAmount + stakeAmount * 2 + stakeAmount / 2;
        assertEq(staking.totalStaked(), totalStaked);
        assertEq(stakingToken.balanceOf(user1), INITIAL_USER_BALANCE - totalStaked);

        // test weight delta 1000 * 0.5 + 2000 * 0.625 + 500 * 0.55
        assertEq(staking.userWeightDelta(user1, startDay), (500 + 625 * 2 + 550 * 0.5) * 10**18);
        assertEq(staking.totalWeightDelta(startDay), (500 + 625 * 2 + 550 * 0.5) * 10**18);

        assertEq(staking.userWeightDelta(user1, startDay + 30), -(550 * 0.5) * 10**18);
        assertEq(staking.totalWeightDelta(startDay + 30), -(550 * 0.5) * 10**18);

        assertEq(staking.userWeightDelta(user1, startDay + 90), -(625 * 2) * 10**18);
        assertEq(staking.totalWeightDelta(startDay + 90), -(625 * 2) * 10**18);

    }

    function test_Stake_RevertIfPaused() public {
        uint256 amount = MIN_STAKING_AMOUNT;
        
        staking.pause();
        
        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        vm.expectRevert();
        staking.stake(amount, RewardsStaking.LockType.LIQUID);
        vm.stopPrank();
    }

    function test_Stake_MultipleUsersStaking() public {
        uint256 stakeAmount1 = 1000 * 10**18;
        uint256 stakeAmount2 = 1000 * 10**18;
        uint256 stakeAmount3 = 1000 * 10**18;
        
        // Multiple users stake
        vm.startPrank(user1);
        stakingToken.approve(address(staking), stakeAmount1);
        staking.stake(stakeAmount1, RewardsStaking.LockType.LIQUID);
        vm.stopPrank();

        
        vm.startPrank(user2);
        stakingToken.approve(address(staking), stakeAmount2);
        staking.stake(stakeAmount2, RewardsStaking.LockType.LOCK_1M);
        vm.stopPrank();
        
        vm.startPrank(user3);
        stakingToken.approve(address(staking), stakeAmount3);
        staking.stake(stakeAmount3, RewardsStaking.LockType.LOCK_3M);
        vm.stopPrank();
        
        assertEq(staking.totalStaked(), stakeAmount1 + stakeAmount2 + stakeAmount3);
        assertEq(staking.getUserPositionCount(user1), 1);
        assertEq(staking.getUserPositionCount(user2), 1);
        assertEq(staking.getUserPositionCount(user3), 1);

        uint256 deploymentDay = staking.deploymentDay();
        uint256 startDay = deploymentDay + 1;

        assertEq(staking.userWeightDelta(user1, startDay), 500 * 10**18);
        assertEq(staking.userWeightDelta(user2, startDay), 550 * 10**18);
        assertEq(staking.userWeightDelta(user3, startDay), 625 * 10**18);
        assertEq(staking.totalWeightDelta(startDay), (500 + 550 + 625) * 10**18);

        assertEq(staking.userWeightDelta(user1, startDay + 30), 0);
        assertEq(staking.userWeightDelta(user2, startDay + 30), -550 * 10**18);
        assertEq(staking.userWeightDelta(user3, startDay + 30), 0);
        assertEq(staking.totalWeightDelta(startDay + 30), -550 * 10**18);

        assertEq(staking.userWeightDelta(user1, startDay + 90), 0);
        assertEq(staking.userWeightDelta(user2, startDay + 90), 0);
        assertEq(staking.userWeightDelta(user3, startDay + 90), -625 * 10**18);
        assertEq(staking.totalWeightDelta(startDay + 90), -625 * 10**18);
    }

    function test_TopUp() public {
        uint256 topUpAmount = 1000 * 10**18;
        
        staking.addRewardToken(address(rewardToken1));
        
        rewardToken1.approve(address(staking), topUpAmount);
        staking.topUp(address(rewardToken1), topUpAmount);
        
        assertEq(rewardToken1.balanceOf(address(staking)), topUpAmount);
        uint256 totalEmission = 0;
        for (uint i = 0; i < 90; i++) {
            uint256 emission = staking.emissionsByToken(address(rewardToken1), i);
            totalEmission += emission;
        }
        assertTrue(totalEmission <= topUpAmount);
        console.log(totalEmission);
        // console.log(staking.emissionsByToken(address(rewardToken1), 0));
        // console.log(staking.emissionsByToken(address(rewardToken1), 89));
    }
    
    function test_TopUp_RevertIfZeroAmount() public {
        staking.addRewardToken(address(rewardToken1));
        
        vm.expectRevert(RewardsStaking.InvalidAmount.selector);
        staking.topUp(address(rewardToken1), 0);
    }
    
    function test_TopUp_RevertIfInvalidToken() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18, 1000000 * 10**18);
        
        staking.addRewardToken(address(rewardToken1));
        
        vm.expectRevert(RewardsStaking.InvalidRewardToken.selector);
        staking.topUp(address(invalidToken), 1000 * 10**18);
    }
    
    function test_TopUp_RevertIfPaused() public {
        staking.pause();
        
        staking.addRewardToken(address(rewardToken1));
        
        vm.expectRevert();
        staking.topUp(address(rewardToken1), 1000 * 10**18);
    }

    function test_Withdraw_RevertIfIncorrectIndex() public {
        vm.startPrank(user1);
        stakingToken.approve(address(staking), MIN_STAKING_AMOUNT);
        staking.stake(MIN_STAKING_AMOUNT, RewardsStaking.LockType.LIQUID);
        
        vm.expectRevert();
        staking.withdraw(1);
        vm.stopPrank();
    }
    
    function test_WithdrawLiquid_InitiateCooldown() public {
        uint256 amount = MIN_STAKING_AMOUNT;
        
        vm.startPrank(user1);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LIQUID);
        
        staking.withdraw(0);
        vm.stopPrank();
        
        RewardsStaking.StakingPosition memory position = staking.getUserPosition(user1, 0);
        assertGt(position.cooldownStartDaySinceDeployment, 0);
        assertEq(position.amount, amount); // Amount should still be there
    }
}