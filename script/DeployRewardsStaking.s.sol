// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RewardsStaking} from "../src/RewardsStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployProduction is Script {
    // Address ALTT token in mainnet
    address constant ALTT_TOKEN = 0x1B5cE2a593a840E3ad3549a34D7b3dEc697c114D;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying to production...");
        console.log("Deployer:", deployer);
        console.log("ALTT Token:", ALTT_TOKEN);
        
        // Check that ALTT token exists
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(ALTT_TOKEN)
        }
        require(codeSize > 0, "ALTT token contract does not exist at specified address");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy RewardsStaking contract with real ALTT token and trustedForwarder
        RewardsStaking staking = new RewardsStaking(IERC20(ALTT_TOKEN), 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        
        vm.stopBroadcast();
        
        console.log("=== PRODUCTION DEPLOYMENT SUCCESSFUL ===");
        console.log("Staking Contract:", address(staking));
        console.log("Staking Token (ALTT):", ALTT_TOKEN);
        console.log("========================================");
        
        staking.addRewardToken(ALTT_TOKEN);
    }
}