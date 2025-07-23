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
    address public alice;
    address public bob;
    address public charlie;
    address public user4;
    
    uint256 public constant INITIAL_TOKEN_BALANCE = 1_000_000 * 10**18;
    uint256 public constant INITIAL_USER_BALANCE = 10_000 * 10**18;
    uint256 public constant MIN_STAKING_AMOUNT = 100 * 10**18;
    
    function setUp() public {
        owner = address(this);
        alice = makeAddr("user1");
        bob = makeAddr("user2");
        charlie = makeAddr("user3");
        user4 = makeAddr("user4");
        
        // Deploy tokens
        stakingToken = new MockERC20("Staking Token", "STAKE", 18, INITIAL_TOKEN_BALANCE);
        rewardToken1 = new MockERC20("Reward Token 1", "REW1", 18, INITIAL_TOKEN_BALANCE);
        rewardToken2 = new MockERC20("Reward Token 2", "REW2", 18, INITIAL_TOKEN_BALANCE);
        
        // Deploy staking contract
        staking = new RewardsStaking(stakingToken);
        
        // Transfer tokens to users
        stakingToken.transfer(alice, 10_000 * 10**18);
        stakingToken.transfer(bob, 10_000 * 10**18);
        stakingToken.transfer(charlie, 10_000 * 10**18);
        stakingToken.transfer(user4, 10_000 * 10**18);
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
        
        vm.startPrank(alice);
        stakingToken.approve(address(staking), amount);
        vm.expectRevert(RewardsStaking.InvalidAmount.selector);
        staking.stake(amount, RewardsStaking.LockType.LIQUID, false);
        vm.stopPrank();
    }
    
    function test_Stake_Liquid() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(alice);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LIQUID, false);
        vm.stopPrank();
        
        // test position
        assertEq(staking.getUserPositionCount(alice), 1);
        RewardsStaking.StakingPosition memory position = staking.getUserPosition(alice, 0);
        assertEq(position.amount, amount);
        assertEq(uint(position.lockType), uint(RewardsStaking.LockType.LIQUID));
        assertEq(position.cooldownEndDaySinceDeployment, 0);
        uint256 deploymentDay = staking.deploymentDay();
        uint256 startDay = deploymentDay + 1;
        assertEq(position.startDaySinceDeployment, startDay);
        assertEq(position.unlockDaySinceDeployment, type(uint32).max);

        assertEq(staking.totalStaked(), amount);
        assertEq(stakingToken.balanceOf(alice), INITIAL_USER_BALANCE - amount);

        // test weight delta 1000 * 10**18 * 500 / 1000
        assertEq(staking.userWeightDelta(alice, startDay), 500 * 10**18);
        assertEq(staking.totalWeightDelta(startDay), 500 * 10**18);
    }
    
    function test_Stake_Locked() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(alice);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LOCK_3M, false);
        vm.stopPrank();
        
        uint256 deploymentDay = staking.deploymentDay();
        uint256 startDay = deploymentDay + 1;
        
        RewardsStaking.StakingPosition memory position = staking.getUserPosition(alice, 0);
        assertEq(position.amount, amount);
        assertEq(uint(position.lockType), uint(RewardsStaking.LockType.LOCK_3M));
        assertGt(position.unlockDaySinceDeployment, position.startDaySinceDeployment);
        assertEq(position.cooldownEndDaySinceDeployment, 0);
        assertEq(position.startDaySinceDeployment, startDay);
        assertEq(position.unlockDaySinceDeployment, startDay + 90);

        assertEq(staking.totalStaked(), amount);
        assertEq(stakingToken.balanceOf(alice), INITIAL_USER_BALANCE - amount);

        assertEq(staking.userWeightDelta(alice, deploymentDay), 0);
        assertEq(staking.totalWeightDelta(deploymentDay), 0);

        // test weight delta 1000 * 10**18 * 625 / 1000
        assertEq(staking.userWeightDelta(alice, startDay), 625 * 10**18);
        assertEq(staking.totalWeightDelta(startDay), 625 * 10**18);

        assertEq(staking.userWeightDelta(alice, startDay + 90), -625 * 10**18);
        assertEq(staking.totalWeightDelta(startDay + 90), -625 * 10**18);
    }

    function test_Stake_MultiplePositionsPerUser() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        // User creates multiple positions
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LIQUID, false);
        
        stakingToken.approve(address(staking), stakeAmount * 2);
        staking.stake(stakeAmount * 2, RewardsStaking.LockType.LOCK_3M, false);
        
        stakingToken.approve(address(staking), stakeAmount / 2);
        staking.stake(stakeAmount / 2, RewardsStaking.LockType.LOCK_1M, false);
        vm.stopPrank();
        
        assertEq(staking.getUserPositionCount(alice), 3);
        
        // Check each position
        RewardsStaking.StakingPosition memory pos0 = staking.getUserPosition(alice, 0);
        RewardsStaking.StakingPosition memory pos1 = staking.getUserPosition(alice, 1);
        RewardsStaking.StakingPosition memory pos2 = staking.getUserPosition(alice, 2);
        
        assertEq(pos0.amount, stakeAmount);
        uint256 deploymentDay = staking.deploymentDay();
        uint256 startDay = deploymentDay + 1;
        
        assertEq(uint(pos0.lockType), uint(RewardsStaking.LockType.LIQUID));
        assertEq(pos0.startDaySinceDeployment, startDay);
        assertEq(pos0.unlockDaySinceDeployment, type(uint32).max);
        assertEq(pos0.cooldownEndDaySinceDeployment, 0);
        
        assertEq(pos1.amount, stakeAmount * 2);
        assertEq(uint(pos1.lockType), uint(RewardsStaking.LockType.LOCK_3M));
        assertEq(pos1.startDaySinceDeployment, startDay);
        assertEq(pos1.unlockDaySinceDeployment, startDay + 90);
        assertEq(pos1.cooldownEndDaySinceDeployment, 0);
        
        assertEq(pos2.amount, stakeAmount / 2);
        assertEq(uint(pos2.lockType), uint(RewardsStaking.LockType.LOCK_1M));
        assertEq(pos2.startDaySinceDeployment, startDay);
        assertEq(pos2.unlockDaySinceDeployment, startDay + 30);
        assertEq(pos2.cooldownEndDaySinceDeployment, 0);

        uint256 totalStaked = stakeAmount + stakeAmount * 2 + stakeAmount / 2;
        assertEq(staking.totalStaked(), totalStaked);
        assertEq(stakingToken.balanceOf(alice), INITIAL_USER_BALANCE - totalStaked);

        // test weight delta 1000 * 0.5 + 2000 * 0.625 + 500 * 0.55
        assertEq(staking.userWeightDelta(alice, startDay), (500 + 625 * 2 + 550 * 0.5) * 10**18);
        assertEq(staking.totalWeightDelta(startDay), (500 + 625 * 2 + 550 * 0.5) * 10**18);

        assertEq(staking.userWeightDelta(alice, startDay + 30), -(550 * 0.5) * 10**18);
        assertEq(staking.totalWeightDelta(startDay + 30), -(550 * 0.5) * 10**18);

        assertEq(staking.userWeightDelta(alice, startDay + 90), -(625 * 2) * 10**18);
        assertEq(staking.totalWeightDelta(startDay + 90), -(625 * 2) * 10**18);

    }

    function test_Stake_WithClaim() public {
        uint256 stakeAmount = MIN_STAKING_AMOUNT;
        uint256 topUpAmount = 1000 * 10**18;

        staking.addRewardToken(address(rewardToken1));
        rewardToken1.approve(address(staking), topUpAmount);
        staking.topUp(address(rewardToken1), topUpAmount);

        uint256 initialStakingBalance = stakingToken.balanceOf(alice);
        uint256 initialRewardsBalance = rewardToken1.balanceOf(alice);

        // User stakes
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LOCK_12M, true);

        assertEq(stakingToken.balanceOf(alice), initialStakingBalance - stakeAmount);
        console.log("Rewards balance should be same as before");
        assertEq(rewardToken1.balanceOf(alice), initialRewardsBalance);
        
        // Skip some time
        vm.warp(block.timestamp + 2 days);
        
        // User stakes again with claiming rewards
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LOCK_12M, true);
        vm.stopPrank();

        uint256 balanceRewardsAfter2ndStake = rewardToken1.balanceOf(alice);
        
        console.log("Rewards balance after 2nd stake should be greater than before");
        assertGt(balanceRewardsAfter2ndStake, initialRewardsBalance);
    }

    function test_Withdraw_WithClaim() public {
        uint256 stakeAmount = MIN_STAKING_AMOUNT;
        uint256 topUpAmount = 1000 * 10**18;

        uint256 initialStakingBalance = stakingToken.balanceOf(alice);
        uint256 initialRewardsBalance = rewardToken1.balanceOf(alice);

        // User stakes
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LOCK_12M, false);
        vm.stopPrank();

        // skip 1 day because satking start from next day, but topUp applied in day of topup 
        vm.warp(block.timestamp + 1 days);

        staking.addRewardToken(address(rewardToken1));
        rewardToken1.approve(address(staking), topUpAmount);
        staking.topUp(address(rewardToken1), topUpAmount);

        assertEq(stakingToken.balanceOf(alice), initialStakingBalance - stakeAmount);
        assertEq(rewardToken1.balanceOf(alice), initialRewardsBalance);
        assertEq(initialRewardsBalance, 0);

        // Skip some time for rewards to accrue
        vm.warp(block.timestamp + 500 days);

        // Balances before withdraw
        uint256 beforeWithdrawStaking = stakingToken.balanceOf(alice);
        uint256 beforeWithdrawRewards = rewardToken1.balanceOf(alice);

        // User withdraws with claim=true
        vm.startPrank(alice);
        staking.withdraw(0, true);
        vm.stopPrank();

        uint256 afterWithdrawStaking = stakingToken.balanceOf(alice);
        uint256 afterWithdrawRewards = rewardToken1.balanceOf(alice);

        console.log(stakingToken.balanceOf(address(staking)));
        assertEq(afterWithdrawStaking, beforeWithdrawStaking + stakeAmount);
        assertGt(afterWithdrawRewards, beforeWithdrawRewards);
        console.log("Rewards balance after withdraw should be greater than before");
        assertEq(afterWithdrawRewards - initialRewardsBalance, topUpAmount);
    }

    function test_Stake_RevertIfPaused() public {
        uint256 amount = MIN_STAKING_AMOUNT;
        
        staking.pause();
        
        vm.startPrank(alice);
        stakingToken.approve(address(staking), amount);
        vm.expectRevert();
        staking.stake(amount, RewardsStaking.LockType.LIQUID, false);
        vm.stopPrank();
    }

    function test_Stake_MultipleUsersStaking() public {
        uint256 stakeAmount1 = 1000 * 10**18;
        uint256 stakeAmount2 = 1000 * 10**18;
        uint256 stakeAmount3 = 1000 * 10**18;
        
        // Multiple users stake
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakeAmount1);
        staking.stake(stakeAmount1, RewardsStaking.LockType.LIQUID, false);
        vm.stopPrank();

        
        vm.startPrank(bob);
        stakingToken.approve(address(staking), stakeAmount2);
        staking.stake(stakeAmount2, RewardsStaking.LockType.LOCK_1M, false);
        vm.stopPrank();
        
        vm.startPrank(charlie);
        stakingToken.approve(address(staking), stakeAmount3);
        staking.stake(stakeAmount3, RewardsStaking.LockType.LOCK_3M, false);
        vm.stopPrank();
        
        assertEq(staking.totalStaked(), stakeAmount1 + stakeAmount2 + stakeAmount3);
        assertEq(staking.getUserPositionCount(alice), 1);
        assertEq(staking.getUserPositionCount(bob), 1);
        assertEq(staking.getUserPositionCount(charlie), 1);

        uint256 deploymentDay = staking.deploymentDay();
        uint256 startDay = deploymentDay + 1;

        assertEq(staking.userWeightDelta(alice, startDay), 500 * 10**18);
        assertEq(staking.userWeightDelta(bob, startDay), 550 * 10**18);
        assertEq(staking.userWeightDelta(charlie, startDay), 625 * 10**18);
        assertEq(staking.totalWeightDelta(startDay), (500 + 550 + 625) * 10**18);

        assertEq(staking.userWeightDelta(alice, startDay + 30), 0);
        assertEq(staking.userWeightDelta(bob, startDay + 30), -550 * 10**18);
        assertEq(staking.userWeightDelta(charlie, startDay + 30), 0);
        assertEq(staking.totalWeightDelta(startDay + 30), -550 * 10**18);

        assertEq(staking.userWeightDelta(alice, startDay + 90), 0);
        assertEq(staking.userWeightDelta(bob, startDay + 90), 0);
        assertEq(staking.userWeightDelta(charlie, startDay + 90), -625 * 10**18);
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
        vm.startPrank(alice);
        stakingToken.approve(address(staking), MIN_STAKING_AMOUNT);
        staking.stake(MIN_STAKING_AMOUNT, RewardsStaking.LockType.LIQUID, false);
        
        vm.expectRevert();
        staking.withdraw(1, false);
        vm.stopPrank();
    }
    
    function test_Withdraw_RevertIfLocked() public {
        uint256 amount = MIN_STAKING_AMOUNT;
        
        vm.startPrank(alice);

        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LOCK_1M, false);

        // Try to withdraw before unlock
        vm.warp(block.timestamp + 30 days); // staking starts on block.timestamp + 1 and ends on block.timestamp + 30 days
        
        vm.expectRevert(RewardsStaking.PositionLocked.selector);
        staking.withdraw(0, false);

        vm.stopPrank();
    }

    function test_WithdrawLiquid_InitiateCooldown() public {
        uint256 amount = MIN_STAKING_AMOUNT;
        
        vm.startPrank(alice);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LIQUID, false);
        
        staking.withdraw(0, false);
        vm.stopPrank();
        
        RewardsStaking.StakingPosition memory position = staking.getUserPosition(alice, 0);
        assertEq(position.cooldownEndDaySinceDeployment, 7);
        assertEq(position.amount, amount); // Amount should still be there
    }

    function test_WithdrawLiquid_RevertIfCooldownNotFinished() public {
        uint256 amount = MIN_STAKING_AMOUNT;
        
        vm.startPrank(alice);
        
        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LIQUID, false);
        
        // Initiate cooldown
        staking.withdraw(0, false);
        
        // Try to withdraw before cooldown
        vm.warp(block.timestamp + 6 days);
        
        vm.expectRevert(RewardsStaking.CooldownNotFinished.selector);
        staking.withdraw(0, false);

        vm.stopPrank();
    }
    
    function test_WithdrawLiquid_AfterCooldown() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(alice);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LIQUID, false);
        
        // Initiate cooldown
        staking.withdraw(0, false);
        
        // Skip cooldown period
        vm.warp(block.timestamp + 7 days);
        
        uint256 balanceBefore = stakingToken.balanceOf(alice);
        
        staking.withdraw(0, false);
        
        assertEq(stakingToken.balanceOf(alice), balanceBefore + amount);
        assertEq(staking.totalStaked(), 0);
        
        RewardsStaking.StakingPosition memory position = staking.getUserPosition(alice, 0);
        assertEq(position.amount, 0);

        vm.stopPrank();
    }
    
    function test_WithdrawLocked_AfterUnlock() public {
        uint256 amount = MIN_STAKING_AMOUNT;
        
        vm.startPrank(alice);

        stakingToken.approve(address(staking), amount);
        staking.stake(amount, RewardsStaking.LockType.LOCK_1M, false);
        
        // Skip lock period
        vm.warp(block.timestamp + 31 days);
        
        uint256 balanceBefore = stakingToken.balanceOf(alice);
        
        staking.withdraw(0, false);
        
        assertEq(stakingToken.balanceOf(alice), balanceBefore + amount);
        assertEq(staking.totalStaked(), 0);
        
        vm.stopPrank();
    }
    
    function test_Withdraw_RevertIfPositionNotExists() public {
        vm.prank(alice);
        vm.expectRevert(RewardsStaking.PositionNotExists.selector);
        staking.withdraw(0, false);
    }
    
    function test_ClaimRewards() public {
        uint256 stakeAmount = MIN_STAKING_AMOUNT;
        uint256 topUpAmount = 1000 * 10**18;
        
        staking.addRewardToken(address(rewardToken1));
        
        // Top up rewards
        rewardToken1.approve(address(staking), topUpAmount);
        staking.topUp(address(rewardToken1), topUpAmount);
        
        // User stakes
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LIQUID, false);
        vm.stopPrank();
        
        // Skip some time
        vm.warp(block.timestamp + 2 days);
        
        uint256 balanceBefore = rewardToken1.balanceOf(alice);
        
        vm.prank(alice);
        staking.claim();
        
        assertGt(rewardToken1.balanceOf(alice), balanceBefore);
    }

    function test_ClaimRewards_MultipleClaims() public {
        uint256 stakeAmount = MIN_STAKING_AMOUNT;
        uint256 topUpAmount = 1000 * 10**18;
        
        staking.addRewardToken(address(rewardToken1));
        rewardToken1.approve(address(staking), topUpAmount);
        staking.topUp(address(rewardToken1), topUpAmount);
        
        // User stakes
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LIQUID, false);
        
        // Skip some time
        vm.warp(block.timestamp + 2 days);
        
        uint256 balanceBefore0 = rewardToken1.balanceOf(alice);
        staking.claim();
        uint256 balanceAfter1Claim = rewardToken1.balanceOf(alice);

        vm.warp(block.timestamp + 1 days);
        staking.claim();
        uint256 balanceAfter2Claim = rewardToken1.balanceOf(alice);
        vm.stopPrank();
        
        console.log("Rewards balance should be greater than before");
        assertEq(balanceBefore0, 0);
        assertGt(balanceAfter1Claim, balanceBefore0);
        console.log("Rewards balance after 2nd claim should be greater than before");
        assertGt(balanceAfter2Claim, balanceAfter1Claim);
    }

    // order of claim and withdraw doesnt matter
    function test_ClaimRewards_WithWithdrawal() public {
        uint256 stakeAmount = MIN_STAKING_AMOUNT;
        uint256 topUpAmount = 1000 * 10**18;
        
        staking.addRewardToken(address(rewardToken1));
        rewardToken1.approve(address(staking), topUpAmount);
        staking.topUp(address(rewardToken1), topUpAmount);
        
        // 3 users stakes
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LOCK_1M, false);
        vm.stopPrank();

        vm.startPrank(bob);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LOCK_1M, false);
        vm.stopPrank();

        vm.startPrank(charlie);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LOCK_1M, false);
        vm.stopPrank();
        
        
        // Skip some time
        vm.warp(block.timestamp + 31 days);
        
        uint256 aliceRewardsBalanceBefore = rewardToken1.balanceOf(alice);
        uint256 aliceStakingBalanceBefore = stakingToken.balanceOf(alice);
        
        vm.startPrank(alice);
        staking.claim();
        staking.withdraw(0, false);
        vm.stopPrank();
        
        uint256 aliceRewardsBalanceAfter = rewardToken1.balanceOf(alice);
        uint256 aliceStakingBalanceAfter = stakingToken.balanceOf(alice);

        assertGt(aliceRewardsBalanceAfter, aliceRewardsBalanceBefore);
        assertEq(aliceStakingBalanceAfter - aliceStakingBalanceBefore, stakeAmount);

        uint256 bobRewardsBalanceBefore = rewardToken1.balanceOf(bob);
        uint256 bobStakingBalanceBefore = stakingToken.balanceOf(bob);
        
        vm.startPrank(bob);
        staking.withdraw(0, false);
        staking.claim();
        vm.stopPrank();
        
        uint256 bobRewardsBalanceAfter = rewardToken1.balanceOf(bob);
        uint256 bobStakingBalanceAfter = stakingToken.balanceOf(bob);

        assertGt(bobRewardsBalanceAfter, bobRewardsBalanceBefore);
        assertEq(bobStakingBalanceAfter - bobStakingBalanceBefore, stakeAmount);

        uint256 charlieRewardsBalanceBefore = rewardToken1.balanceOf(charlie);
        uint256 charlieStakingBalanceBefore = stakingToken.balanceOf(charlie);

        vm.prank(charlie);
        staking.withdraw(0, true);
        
        uint256 charlieRewardsBalanceAfter = rewardToken1.balanceOf(charlie);
        uint256 charlieStakingBalanceAfter = stakingToken.balanceOf(charlie);

        assertGt(charlieRewardsBalanceAfter, charlieRewardsBalanceBefore);
        assertEq(charlieStakingBalanceAfter - charlieStakingBalanceBefore, stakeAmount);

        assertEq(staking.totalStaked(), 0);
        assertEq(aliceRewardsBalanceAfter - aliceRewardsBalanceBefore, bobRewardsBalanceAfter - bobRewardsBalanceBefore);
        assertEq(aliceRewardsBalanceAfter - aliceRewardsBalanceBefore, charlieRewardsBalanceAfter - charlieRewardsBalanceBefore);
    }
    
    function test_ClaimRewards_IfNothingToClaim() public {
        uint256 stakeAmount = MIN_STAKING_AMOUNT;

        staking.addRewardToken(address(rewardToken1));
        
        // User stakes
        vm.startPrank(alice);

        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LIQUID, false);
        
        // Try to claim immediately (nothing to claim)
        uint256 balanceBefore = rewardToken1.balanceOf(alice);
        staking.claim();
        uint256 balanceAfter = rewardToken1.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore);

        vm.stopPrank();
    }
    
    function test_ClaimRewards_RevertIfEmptyRewardTokens() public {
        uint256 stakeAmount = MIN_STAKING_AMOUNT;
        
        // User stakes
        vm.startPrank(alice);

        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LIQUID, false);
        
        // Skip some time
        vm.warp(block.timestamp + 2 days);
        
        uint256 balanceBefore = rewardToken1.balanceOf(alice);
        staking.claim();
        uint256 balanceAfter = rewardToken1.balanceOf(alice);
        assertEq(balanceAfter, balanceBefore);

        vm.stopPrank();
    }
    
    function test_TopUp_DifferentLockTypesWeights() public {
        uint256 stakeAmount = MIN_STAKING_AMOUNT;
        
        // Stakes with different lock types
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LIQUID, false);
        vm.stopPrank();
        
        vm.startPrank(bob);
        stakingToken.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount, RewardsStaking.LockType.LOCK_12M, false);
        vm.stopPrank();
        
        // Top up rewards
        staking.addRewardToken(address(rewardToken1));
        rewardToken1.approve(address(staking), 1000 * 10**18);
        staking.topUp(address(rewardToken1), 1000 * 10**18);
        
        // Skip time
        vm.warp(block.timestamp + 2 days);
        
        // Claim rewards
        vm.prank(alice);
        staking.claim();
        
        vm.prank(bob);
        staking.claim();
        
        // User2 should have more rewards due to higher lock multiplier
        assertGt(rewardToken1.balanceOf(bob), rewardToken1.balanceOf(alice));
    }
    
    function test_Pause_Unpause() public {
        staking.pause();
        assertTrue(staking.paused());
        
        staking.unpause();
        assertFalse(staking.paused());
    }
    
    function test_OnlyOwner_Functions() public {
        vm.prank(alice);
        vm.expectRevert();
        staking.pause();
        
        vm.prank(alice);
        vm.expectRevert();
        staking.unpause();
        
        vm.prank(alice);
        vm.expectRevert();
        staking.addRewardToken(address(rewardToken1));
        
        vm.prank(alice);
        vm.expectRevert();
        staking.removeRewardToken(address(rewardToken1));
    }
    
    function test_RejectEther() public {
        vm.expectRevert("Contract does not accept ETH");
        address(staking).call{value: 1 ether}("");
    }

    function test_RejectEther2() public {
        vm.expectRevert("Contract does not accept ETH");
    payable(address(staking)).transfer(1 ether);
    }

    function test_RevertOnFallback() public {
        vm.expectRevert("Fallback function not allowed");
        (bool success, ) = address(staking).call{value: 1 ether}(
            abi.encodeWithSignature("nonExistentFunction()")
        );
    }
    
    function test_GetCurrentDaySinceDeployment() public {
        uint256 currentDay = staking.getCurrentDaySinceDeployment();
        assertEq(currentDay, 0);
        
        vm.warp(block.timestamp + 2 days);
        currentDay = staking.getCurrentDaySinceDeployment();
        assertEq(currentDay, 2);
    }
    
    function test_EmissionDecay() public {
        uint256 topUpAmount = 90 * 10**18; // 90 * 10**18 tokens for 90 days
        
        staking.addRewardToken(address(rewardToken1));
        rewardToken1.approve(address(staking), topUpAmount);
        staking.topUp(address(rewardToken1), topUpAmount);
        
        // Check that emissions are distributed over 90 days with decay
        uint256 day1Emissions = staking.emissionsByToken(address(rewardToken1), 0);
        uint256 day90Emissions = staking.emissionsByToken(address(rewardToken1), 89);

        uint256 tottalEmissions = 0;
        for (uint256 i = 0; i < 90; i++) {
            tottalEmissions += staking.emissionsByToken(address(rewardToken1), i);

            assertGt(staking.emissionsByToken(address(rewardToken1), i), staking.emissionsByToken(address(rewardToken1), i + 1)); // next day should have less emissions
        }
        
        assertGt(day1Emissions, 1 * 10**18);
        assertLt(day90Emissions, 1 * 10**18);
        assertEq(tottalEmissions, topUpAmount);
    }
}