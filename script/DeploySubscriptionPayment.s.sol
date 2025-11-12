// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SubscriptionPayment.sol";

/**
 * @title DeploySubscriptionPayment
 * @notice Deployment script for ultra-simple SubscriptionPayment contract
 * 
 * Usage:
 * forge script script/DeploySubscriptionPayment.s.sol:DeploySubscriptionPayment \
 *   --rpc-url $BASE_RPC_URL \
 *   --broadcast \
 *   --verify
 * 
 * Environment variables:
 * - PAYMENT_TOKEN: WETH address (default: Base mainnet WETH)
 * - PRIVATE_KEY: Deployer private key
 */
contract DeploySubscriptionPayment is Script {
    // Base mainnet WETH address
    address constant DEFAULT_WETH = 0x4200000000000000000000000000000000000006;
    
    function run() external {
        // Read environment variables
        address paymentToken = vm.envOr("PAYMENT_TOKEN", DEFAULT_WETH);
        
        // Get deployer private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy contract
        SubscriptionPayment subscriptionPayment = new SubscriptionPayment(paymentToken);
        
        console.log("SubscriptionPayment deployed at:", address(subscriptionPayment));
        console.log("Payment token:", paymentToken);
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        // Print summary
        console.log("\n=== Deployment Summary ===");
        console.log("Contract:", address(subscriptionPayment));
        console.log("Payment token:", address(subscriptionPayment.paymentToken()));
        
        // Print environment variable for backend
        console.log("\n=== Backend Configuration ===");
        console.log("Add to backend/worker/.env:");
        console.log("SUBSCRIPTION_CONTRACT_ADDRESS=", address(subscriptionPayment));
        
        // Print usage example
        console.log("\n=== Usage Example ===");
        console.log("Backend calculates distribution and calls:");
        console.log("processSubscription(");
        console.log("  subscriber,");
        console.log("  creator,");
        console.log("  6,  // purchased months");
        console.log("  7,  // total months (with bonus)");
        console.log("  [creator, ecosystem, team],  // recipients");
        console.log("  [0.432e18, 0.096e18, 0.072e18]  // amounts");
        console.log(")");
    }
}
