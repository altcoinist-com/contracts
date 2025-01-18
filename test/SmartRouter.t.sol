// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "../src/SmartRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

// use only on fork
contract SmartRouterTest is Test {

    address public constant ALTT = 0x1B5cE2a593a840E3ad3549a34D7b3dEc697c114D;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    SmartRouter public router;
    function setUp() public {
        address[] memory tokens = new address[](5);
        tokens[0] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        tokens[1] = 0x4200000000000000000000000000000000000006;
        tokens[2] = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
        tokens[3] = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
        tokens[4] = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
        router = new SmartRouter(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a, tokens);
    }

    function test_smartQuote() public {
        (bool success, bytes memory result) = address(router).call(abi.encodeWithSignature('exactInputPath(address,address,uint256)', ALTT, USDC, 100 ether));

        //abi.encodePacked(tokenIn, v3Fees[j], tokens[i], v3Fees[k], tokenOut);
    }
}
