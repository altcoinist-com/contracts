pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "./TestEnv.t.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";


contract CreatorTokenFactoryTest is Test {
    TestEnv env;
    SubscribeRegistry registry;
    CreatorTokenFactory factory;
    address alice; address bob;

    function setUp() public {
        env = new TestEnv();
        registry = env.registry();
        factory = env.creatorFactory();
        alice = env.accounts(1);
        bob = env.accounts(2);
    }

    function initPrice(uint256 m, uint256 l) internal {
        vm.startPrank(alice);
        registry.setSubPrice(m, l, "Jsmith");
        vm.stopPrank();
    }

    function test_soulboundTokensCannotMove() public {
        initPrice(1e18, 5e18);
        vm.startPrank(bob);
        registry.subscribe(SubscribeRegistry.SubscribeParams(alice, bob, SubscribeRegistry.packages.MONTHLY, 1, 1, address(0)));
        assertEq(factory.balanceOf(bob, uint256(uint160(alice))), 1);
        vm.expectRevert("soulbound");
        factory.safeTransferFrom(bob, alice, uint256(uint160(alice)), 1, bytes(""));
    }
}
