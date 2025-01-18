// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SmartRouter.sol";

interface IWETH {
        function deposit() external payable;
        function approve(address,uint256) external;
}

contract DeploySmartRouter is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerPrivateKey);
        address[] memory tokens = new address[](5);
        tokens[0] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        tokens[1] = 0x4200000000000000000000000000000000000006;
        tokens[2] = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
        tokens[3] = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
        tokens[4] = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
        vm.startBroadcast(deployerPrivateKey);
        SmartRouter router = new SmartRouter(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a, tokens);
        console.log("SmartRouter: %s", address(router));

        // for debugging & testing
        IWETH weth = IWETH(0x4200000000000000000000000000000000000006);
        weth.deposit{value: 100 ether}();
        weth.approve(address(router), 100 ether);

        vm.stopBroadcast();
    }
}
