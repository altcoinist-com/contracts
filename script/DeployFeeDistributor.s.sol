// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/FeeDistributor.sol";

/**
 * @title DeployFeeDistributor
 * @dev Deployment script for FeeDistributor with CREATE2 support
 */
contract DeployFeeDistributor is Script {
    // Fixed salt for deterministic deployment across chains
    bytes32 public constant SALT = keccak256("altcoinist-fee-distributor");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        console.log("=== FeeDistributor Deployment ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Salt:", vm.toString(SALT));

        FeeDistributor feeDistributor = new FeeDistributor{salt: SALT}();

        // This address will be IDENTICAL on all chains using the same salt!
        console.log("Deployed Address:", address(feeDistributor));
        console.log("Deployment Successful!");
        vm.stopBroadcast();
    }
}
