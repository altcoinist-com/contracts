// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RewardsStaking} from "../src/RewardsStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployProduction is Script {
    // Address ALTT token in mainnet
    address constant ALTT_TOKEN = 0x1B5cE2a593a840E3ad3549a34D7b3dEc697c114D;
    address constant TRUSTED_FORWARDER = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying UUPS upgradeable RewardsStaking to production...");
        console.log("Deployer:", deployer);
        console.log("ALTT Token:", ALTT_TOKEN);
        
        // Check that ALTT token exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(ALTT_TOKEN)
        }
        require(codeSize > 0, "ALTT token contract does not exist at specified address");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy implementation logic
        RewardsStakingUpgradeable logic = new RewardsStakingUpgradeable();

        // 2. Encode initializer data
        bytes memory data = abi.encodeCall(
            RewardsStakingUpgradeable.initialize,
            (IERC20(ALTT_TOKEN), TRUSTED_FORWARDER)
        );

        // 3. Deploy proxy with initializer data
        ERC1967Proxy proxy = new ERC1967Proxy(address(logic), data);

         // 4. Cast proxy to RewardsStakingUpgradeable interface
        RewardsStakingUpgradeable staking = RewardsStakingUpgradeable(address(proxy));

        // 5. Add ALTT as reward token
        staking.addRewardToken(ALTT_TOKEN);
        
        vm.stopBroadcast();
        
        console.log("=== PRODUCTION DEPLOYMENT SUCCESSFUL ===");
        console.log("Logic Contract:", address(logic));
        console.log("Proxy Contract (main address):", address(proxy));
        console.log("Staking Token (ALTT):", ALTT_TOKEN);
        console.log("========================================");
        
    }
}