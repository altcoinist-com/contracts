// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RewardsStaking} from "../../src/RewardsStaking.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockTrustedForwarder} from "../utils/MockTrustedForwarder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RewardsStakingFullCycleTest is Test {
    MockERC20 public stakingToken;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;
    MockTrustedForwarder public trustedForwarder; // mock trustedForwarder
    ERC1967Proxy proxy;
    RewardsStaking logic;
    RewardsStaking public staking;
    
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
        
                
        logic = new RewardsStaking();
        trustedForwarder = new MockTrustedForwarder();

        // 2. Encode initializer
        bytes memory data = abi.encodeCall(
            RewardsStaking.initialize,
            (IERC20(address(stakingToken)), address(trustedForwarder))
        );

        // 3. Deploy proxy with data
        proxy = new ERC1967Proxy(address(logic), data);

        // 4. Cast to interface
        staking = RewardsStaking(payable(address(proxy)));
        
        // Transfer tokens to users
        stakingToken.transfer(alice, 10_000 * 10**18);
        stakingToken.transfer(bob, 10_000 * 10**18);
        stakingToken.transfer(charlie, 10_000 * 10**18);
        stakingToken.transfer(user4, 10_000 * 10**18);
    }
    
    function test_FullStakingCycle() public {
        console.log("=== Testing Full Staking Cycle ===");

        uint256 stakingAmount = 100 * 10**18;

        staking.addRewardToken(address(rewardToken1));
        staking.addRewardToken(address(rewardToken2));
        
        // Day 0: Alice stakes liquid, Bob stakes 3M lock
        console.log("Day 0: Alice and Bob staked");
        vm.startPrank(alice);
        stakingToken.approve(address(staking), stakingAmount);
        staking.stake(stakingAmount, RewardsStaking.LockType.LIQUID, false);
        vm.stopPrank();
        
        vm.startPrank(bob);
        stakingToken.approve(address(staking), stakingAmount);
        staking.stake(stakingAmount, RewardsStaking.LockType.LOCK_3M, false);
        vm.stopPrank();

        vm.startPrank(user4);
        stakingToken.approve(address(staking), stakingAmount * 2);
        staking.stake(stakingAmount * 2, RewardsStaking.LockType.LOCK_3M, false);
        vm.stopPrank();

        console.log("Total staked:", staking.totalStaked());
        assertEq(staking.totalStaked(), stakingAmount * 4);
        console.log("==================== Day 0: Added rewards");
        
        uint256 rewardAmount = 10_000 * 10**18;
        rewardToken1.approve(address(staking), rewardAmount);
        staking.topUp(address(rewardToken1), rewardAmount);
        
        uint256 aliceReward1Before0 = rewardToken1.balanceOf(alice);
        uint256 bobReward1Before0 = rewardToken1.balanceOf(bob);
        uint256 charlieReward1Before0 = rewardToken1.balanceOf(charlie);
        uint256 user4Reward1Before0 = rewardToken1.balanceOf(user4);
        
        vm.prank(alice);
        staking.claim();
        
        vm.prank(bob);
        staking.claim();
        
        vm.prank(charlie);
        staking.claim();

        vm.prank(user4);
        staking.claim();

        uint256 aliceReward1After0 = rewardToken1.balanceOf(alice);
        uint256 bobReward1After0 = rewardToken1.balanceOf(bob);
        uint256 charlieReward1After0 = rewardToken1.balanceOf(charlie);
        uint256 user4Reward1After0 = rewardToken1.balanceOf(user4);

        assertEq(aliceReward1After0 - aliceReward1Before0, 0);
        assertEq(bobReward1After0 - bobReward1Before0, 0);
        assertEq(charlieReward1After0 - charlieReward1Before0, 0);
        assertEq(user4Reward1After0 - user4Reward1Before0, 0);
        
        vm.warp(block.timestamp + 5 days);
        console.log("==================== Day 5: Charlie joins with 12M lock");
        
        vm.startPrank(charlie);
        stakingToken.approve(address(staking), stakingAmount * 2);
        staking.stake(stakingAmount * 2, RewardsStaking.LockType.LOCK_12M, false);
        vm.stopPrank();
        console.log("Total staked:", staking.totalStaked());
        assertEq(staking.totalStaked(), stakingAmount * 6);

        vm.warp(block.timestamp + 5 days);
        console.log("==================== Day 10: First rewards claims: ");
        
        uint256 aliceReward1Before = rewardToken1.balanceOf(alice);
        uint256 bobReward1Before = rewardToken1.balanceOf(bob);
        uint256 charlieReward1Before = rewardToken1.balanceOf(charlie);
        uint256 user4Reward1Before = rewardToken1.balanceOf(user4);
        
        vm.prank(alice);
        staking.claim();
        
        vm.prank(bob);
        staking.claim();
        
        vm.prank(charlie);
        staking.claim();

        vm.prank(user4);
        staking.claim();
        
        uint256 aliceReward1After = rewardToken1.balanceOf(alice);
        uint256 bobReward1After = rewardToken1.balanceOf(bob);
        uint256 charlieReward1After = rewardToken1.balanceOf(charlie);
        uint256 user4Reward1After = rewardToken1.balanceOf(user4);
        
        uint256 aliceReward1Claimed = aliceReward1After - aliceReward1Before;
        uint256 bobReward1Claimed = bobReward1After - bobReward1Before;
        uint256 charlieReward1Claimed = charlieReward1After - charlieReward1Before;
        uint256 user4Reward1Claimed = user4Reward1After - user4Reward1Before;

        console.log("Alice:", aliceReward1Claimed);
        console.log("Bob:", bobReward1Claimed);
        console.log("Charlie:", charlieReward1Claimed);
        console.log("User4:", user4Reward1Claimed);
        
        (uint32 bobLastClaimed,,, ) = staking.userData(bob);
        (uint32 charlieLastClaimed,,, ) = staking.userData(charlie);
        (uint32 user4LastClaimed,,, ) = staking.userData(user4);
        
        assertEq(bobLastClaimed, staking.deploymentDay() + 10);
        assertEq(charlieLastClaimed, staking.deploymentDay() + 10);
        assertEq(user4LastClaimed, staking.deploymentDay() + 10);
        
        console.log("Bob should have more rewards than Alice due to higher lock multiplier");
        assertGt(bobReward1Claimed, aliceReward1Claimed);

        console.log("Bob should have 1.25 times more rewards than Alice");
        assertEq(bobReward1Claimed / 625, aliceReward1Claimed / 500);
        
        console.log("User4 should have more rewards than Bob, because he staked twice more tokens in same day");
        assertGt(user4Reward1Claimed, bobReward1Claimed * 2);

        vm.warp(block.timestamp + 5 days);
        console.log("==================== Day 15: Try to withdraw: ");
        console.log("Alice should initiate cooldown by withdrawing with claim");

        uint256 aliceReward1BeforeWithdrawal = rewardToken1.balanceOf(alice);
        uint256 aliceBalanceBeforeWithdrawal = stakingToken.balanceOf(alice);
        vm.prank(alice);
        staking.withdraw(0, true); // Initiate cooldown
        uint256 aliceReward1AfterWithdrawal = rewardToken1.balanceOf(alice);
        uint256 aliceBalanceAfterWithdrawal = stakingToken.balanceOf(alice);

        console.log("Alice should get more rewards than before");
        assertGt(aliceReward1AfterWithdrawal, aliceReward1BeforeWithdrawal);

        console.log("Alice staking tokens balance shouldn't be changed because of cooldown");
        assertEq(aliceBalanceBeforeWithdrawal, aliceBalanceAfterWithdrawal);

        console.log("Bob should not be able to withdraw because of locked");
        vm.prank(bob);
        vm.expectRevert(RewardsStaking.PositionLocked.selector);
        staking.withdraw(0, false);

        console.log("Charlie should not be able to withdraw because of cooldown");
        vm.prank(charlie);
        vm.expectRevert(RewardsStaking.PositionLocked.selector);
        staking.withdraw(0, false);

        console.log("User4 should not be able to withdraw because of cooldown");
        vm.prank(user4);
        vm.expectRevert(RewardsStaking.PositionLocked.selector);
        staking.withdraw(0, false);
        
        vm.warp(block.timestamp + 5 days);
        console.log("==================== Day 20: Alice cooldown is not finished yet");
        
        uint256 aliceReward2BeforeClaim = rewardToken1.balanceOf(alice);
        vm.startPrank(alice);
        staking.claim();
        uint256 aliceReward2AfterClaim = rewardToken1.balanceOf(alice);
        
        console.log("Alice should get the same amount of rewards as before, because of cooldown");
        assertGt(aliceReward2BeforeClaim, 0);
        assertEq(aliceReward2AfterClaim, aliceReward2BeforeClaim);

        vm.expectRevert(RewardsStaking.CooldownNotFinished.selector);
        staking.withdraw(0, false); // try to withdrawal in cooldown
        vm.stopPrank();

        console.log("==================== Day 20: Top up rewards");
        rewardToken1.approve(address(staking), rewardAmount);
        staking.topUp(address(rewardToken1), rewardAmount);
        
        vm.warp(block.timestamp + 1 days);
        console.log("==================== Day 21: Alice cooldown is not finished yet");
        
        vm.prank(alice);
        vm.expectRevert(RewardsStaking.CooldownNotFinished.selector);
        staking.withdraw(0, false);
        
        vm.warp(block.timestamp + 1 days);
        console.log("==================== Day 22: Alice completes withdrawal");
        
        uint256 aliceStakeBalanceBefore = stakingToken.balanceOf(alice);
        
        vm.prank(alice);
        staking.withdraw(0, false); // Complete withdrawal
        
        uint256 aliceStakeBalanceAfter = stakingToken.balanceOf(alice);
        
        console.log("Alice got back:", aliceStakeBalanceAfter - aliceStakeBalanceBefore);
        assertEq(aliceStakeBalanceAfter - aliceStakeBalanceBefore, stakingAmount);
        
        // // Day 30: Claim rewards again
        vm.warp(block.timestamp + 8 days);
        console.log("==================== Day 30: Claim rewards");
        
        
        uint256 bobReward1Before2 = rewardToken1.balanceOf(bob);
        uint256 charlieReward1Before2 = rewardToken1.balanceOf(charlie);
        uint256 aliceReward1Before2 = rewardToken1.balanceOf(alice);
        console.log("Bob rewards before claim:", bobReward1Before2);
        console.log("Charlie rewards before claim:", charlieReward1Before2);
        console.log("Alice rewards before claim:", aliceReward1Before2);
        
        vm.prank(bob);
        staking.claim();
        
        vm.prank(charlie);
        staking.claim();

        vm.prank(alice);
        staking.claim();

        (uint32 aliceLastClaimed2,,, ) = staking.userData(alice);
        (uint32 bobLastClaimed2,,, ) = staking.userData(bob);
        (uint32 charlieLastClaimed2,,, ) = staking.userData(charlie);
        (uint32 user4LastClaimed2,,, ) = staking.userData(user4);

        assertEq(aliceLastClaimed2, staking.deploymentDay() + 30);
        assertEq(bobLastClaimed2, staking.deploymentDay() + 30);
        assertEq(charlieLastClaimed2, staking.deploymentDay() + 30);
        assertEq(user4LastClaimed2, staking.deploymentDay() + 10);
        
        uint256 bobReward1After2 = rewardToken1.balanceOf(bob);
        uint256 charlieReward1After2 = rewardToken1.balanceOf(charlie);
        uint256 aliceReward1After2 = rewardToken1.balanceOf(alice);
        console.log("Bob rewards after claim:", bobReward1After2);
        console.log("Charlie rewards after claim:", charlieReward1After2);
        console.log("Alice rewards after claim:", aliceReward1After2);
        assertEq(aliceReward1After2 - aliceReward1Before2, 0);
        
        console.log("=== Full Staking Cycle Test Complete ===");
    }
}