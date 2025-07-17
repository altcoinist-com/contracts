// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RewardsStaking} from "../src/RewardsStaking.sol";
import {MockERC20} from "../test/utils/MockERC20.sol";

contract DeployRewardsStakingTest is Script {
    function run() external {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // address deployer = vm.addr(deployerPrivateKey);
        
        // console.log("Deploying contracts with the account:", deployer);
        // console.log("Account balance:", deployer.balance);
        
        vm.startBroadcast();
        
        MockERC20 stakingToken = new MockERC20(
            "Test Staking Token",
            "TST",
            18,
            10_000_000 * 10**18
        );
        
        MockERC20 rewardToken2 = new MockERC20(
            "Reward Token 2", 
            "REW2",
            18,
            10_000_000 * 10**18
        );
        
        // Deploy RewardsStaking contract
        RewardsStaking staking = new RewardsStaking(stakingToken);
        
        // Add reward tokens
        staking.addRewardToken(address(stakingToken));
        staking.addRewardToken(address(rewardToken2));
        
        vm.stopBroadcast();
        
        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log("Staking Token:", address(stakingToken));
        console.log("Reward Token 1:", address(stakingToken));
        console.log("Reward Token 2:", address(rewardToken2));
        console.log("Staking Contract:", address(staking));
        console.log("================================");
    }
}