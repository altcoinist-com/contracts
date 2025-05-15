import {Test, console} from "forge-std/Test.sol";
import "forge-std/console.sol";
import { UniswapV2TradeManager } from "../src/SmartRouterUniV2.sol";

contract SmartRouterUniV2 is Test {
    address public constant ROUTER = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address public constant TOKEN = 0xC797Fc5Ca8eF5502aaa0307B9bfC45E877d6Caf5;
    address public constant VIRTUALS = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;
    UniswapV2TradeManager public manager;


    function setUp() public {
        manager = new UniswapV2TradeManager(ROUTER, VIRTUALS);
    }

    function test_buy() public {
        manager.purchaseAsset{value: 1e18}(TOKEN, 1e18, block.timestamp + 20 minutes);
    }
}
