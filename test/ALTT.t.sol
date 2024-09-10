pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./TestEnv.t.sol";
import "forge-std/console.sol";
contract ContractBTest is Test {
    TestEnv env;
    function setUp() public {
        env = new TestEnv();
    }
    function test_correctName() public {
        assertEq(env.altt().symbol(), "ALTT");
    }
}
