// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { UniswapV2TradeManager } from "../src/UniswapV2TradeManager.sol";

contract DeployUniswapV2TradeManager is Script {
        function run() external {
                address  ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
                address  TOKEN = 0xC797Fc5Ca8eF5502aaa0307B9bfC45E877d6Caf5;
                address  VIRTUALS = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;

                uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
                address admin = vm.addr(deployerPrivateKey);

                vm.startBroadcast(deployerPrivateKey);
                UniswapV2TradeManager manager = new UniswapV2TradeManager(ROUTER, VIRTUALS);
                console.log("deployed at", address(manager));
                // for debugging & testing

                //weth.deposit{value: 100 ether}();
                //weth.approve(address(router), 100 ether);

                vm.stopBroadcast();
        }
}
