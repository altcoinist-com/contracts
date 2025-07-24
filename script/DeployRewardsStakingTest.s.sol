// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RewardsStaking} from "../src/RewardsStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockTrustedForwarder} from "../test/utils/MockTrustedForwarder.sol";
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
        
        // Deploy MockForwarder for testing
        MockTrustedForwarder trustedForwarder = new MockTrustedForwarder();
        console.log("MockTrustedForwarder address:", address(trustedForwarder));
        
        // 1. Deploy implementation logic
        RewardsStaking logic = new RewardsStaking();

        // 2. Encode initializer data
        bytes memory data = abi.encodeCall(
            RewardsStaking.initialize,
            (IERC20(address(stakingToken)), address(trustedForwarder))
        );

        // 3. Deploy proxy with initializer data
        ERC1967Proxy proxy = new ERC1967Proxy(address(logic), data);

         // 4. Cast proxy to RewardsStakingUpgradeable interface
        RewardsStaking staking = RewardsStaking(payable(address(proxy)));

        // 5. Add ALTT as reward tokens
        staking.addRewardToken(address(stakingToken));
        staking.addRewardToken(address(rewardToken2));
        
        vm.stopBroadcast();
        
        console.log("=== DEPLOYMENT SUCCESSFUL ===");
        console.log("Logic Contract:", address(logic));
        console.log("Proxy Contract (main address):", address(proxy));
        console.log("Staking Token:", address(stakingToken));
        console.log("Reward Token 1:", address(stakingToken));
        console.log("Reward Token 2:", address(rewardToken2));
        console.log("Staking Contract:", address(staking));
        console.log("================================");
    }
}