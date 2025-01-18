// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ALTT.sol";
import "../src/SubscribeRegistry.sol";
import "../src/StakingFactory.sol";
import "../src/StakingVault.sol";
import "../src/CreatorTokenFactory.sol";
//import "../src/PaymentCollector.sol";
import "../src/PaymentCollectorV2.sol";
import "../src/TWAP.sol";
import "../src/XPRedeem.sol";

struct Call {
    address target;
    bytes callData;
}

interface Multicall {
    function aggregate(Call[] calldata calls) external payable;
}

contract DeployAltt is Script {
        ALTT altt = ALTT(0xa3c51323b901b6D5f8d484e13DFC1a6F47dEb598);

        function run() external {
                vm.startBroadcast();
                uint256 len = 51;
                string memory csvFile = "./script/pools.txt";
                Call[] memory calls = new Call[](len);
                bytes memory cd = abi.encodeWithSignature("initWethConversion()");

                for (uint256 i = 0; i < len; i++) {
                    address to = vm.parseAddress(vm.readLine(csvFile));
                    calls[i] = Call(to, cd);
                }
                Multicall(0xcA11bde05977b3631167028862bE2a173976CA11).aggregate(calls);
                vm.stopBroadcast();
        }
}
