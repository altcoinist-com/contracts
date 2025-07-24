// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RewardsStakingUpgradeable} from "../src/RewardsStaking.sol";
import {MockERC20} from "../test/utils/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockTrustedForwarder} from "../test/utils/MockTrustedForwarder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/RewardsStaking.sol";

contract RewardsStakingV2 is RewardsStakingUpgradeable {
    function version() external pure returns (string memory) {
        return "V2";
    }
}

contract RewardsStakingUpgradeTest is Test {
    RewardsStakingUpgradeable logic;
    RewardsStakingUpgradeable staking;
    ERC1967Proxy proxy;
    MockERC20 token;
    MockTrustedForwarder trustedForwarder; // mock trustedForwarder

    address deployer = address(0xABCD);

    function setUp() public {
        vm.startPrank(deployer);

        // 1. Deploy logic + token
        token = new MockERC20("Test Token", "TST", 18, 10_000_000 * 10**18);
        logic = new RewardsStakingUpgradeable();
        trustedForwarder = new MockTrustedForwarder();

        // 2. Encode initializer
        bytes memory data = abi.encodeCall(
            RewardsStakingUpgradeable.initialize,
            (IERC20(address(token)), address(trustedForwarder))
        );

        // 3. Deploy proxy with data
        proxy = new ERC1967Proxy(address(logic), data);

        // 4. Cast to interface
        staking = RewardsStakingUpgradeable(address(proxy));

        // 5. Add reward token
        staking.addRewardToken(address(token));

        vm.stopPrank();
    }

    function testRewardTokenIsAdded() public {
        assertEq(staking.getRewardTokensLength(), 1);
    }

    function testUpgradeToV2() public {
        vm.startPrank(deployer);

        // 6. Deploy V2 logic
        RewardsStakingV2 v2 = new RewardsStakingV2();

        // 7. Upgrade
        staking.upgradeTo(address(v2));

        // 8. Check that old state still present
        assertEq(staking.getRewardTokensLength(), 1);

        // 9. Check new logic via cast
        string memory version = RewardsStakingV2(address(staking)).version();
        assertEq(version, "V2");

        vm.stopPrank();
    }
}