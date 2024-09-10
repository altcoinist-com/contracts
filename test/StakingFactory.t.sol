pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "./TestEnv.t.sol";
import "forge-std/console.sol";
import "../src/StakingFactory.sol";
contract StakingFactoryTest is Test {
    TestEnv env;
    function setUp() public {
        env = new TestEnv();
    }

    function test_cantOpenPoolWithEOA() public {
        vm.startPrank(env.accounts(1));
        StakingFactory stakingFactory = env.stakingFactory();
        address bob = env.accounts(2);
        vm.expectRevert(bytes("PD"));
        stakingFactory.createPool(bob);
    }
}
