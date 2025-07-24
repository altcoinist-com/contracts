// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RewardsStaking} from "../src/RewardsStaking.sol";
import {MockERC20} from "../test/utils/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockTrustedForwarder} from "../test/utils/MockTrustedForwarder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/RewardsStaking.sol";

contract RewardsStakingV2 is RewardsStaking {
    function version() external pure returns (string memory) {
        return "V2";
    }

    function newFunction() external pure returns (string memory) {
        return "Upgraded!";
    }

    function _authorizeUpgrade(address newImpl) internal override onlyOwner {}
}

contract RewardsStakingUpgradeTest is Test {
    RewardsStaking logic;
    RewardsStaking staking;
    ERC1967Proxy proxy;
    MockERC20 stakingToken;
    MockTrustedForwarder trustedForwarder; // mock trustedForwarder

    address deployer = address(0xABCD);

    function setUp() public {
        vm.startPrank(deployer);

        // 1. Deploy logic + token
        stakingToken = new MockERC20("Test Token", "TST", 18, 10_000_000 * 10**18);
        logic = new RewardsStaking();
        trustedForwarder = new MockTrustedForwarder();

        // 2. Encode initializer
        bytes memory data = abi.encodeCall(
            RewardsStaking.initialize,
            (IERC20(address(stakingToken)), address(trustedForwarder))
        );

        // 3. Deploy proxy with data
        proxy = new ERC1967Proxy(address(logic), data);

        // 4. Cast to interface
        staking = RewardsStaking(payable(address(proxy)));

        // 5. Add reward token
        staking.addRewardToken(address(stakingToken));

        vm.stopPrank();
    }

    function testCanCallAfterDeploy() public {
        assertEq(address(staking.stakingToken()), address(stakingToken));
    }

    function testUpgradeToV2AndCallNewFunction() public {
        vm.startPrank(deployer);

        // 1. Deploy new logic contract (V2)
        RewardsStakingV2 logicV2 = new RewardsStakingV2();

        // 2. Upgrade
        staking.upgradeToAndCall(address(logicV2), "");

        // 3. Call new function
        string memory result = RewardsStakingV2(payable(address(staking))).newFunction();
        assertEq(result, "Upgraded!");

        string memory version = RewardsStakingV2(payable(address(staking))).version();
        assertEq(version, "V2");

        vm.stopPrank();
    }

    function test_StoragePersistsAcrossUpgrade() public {
        vm.startPrank(deployer);

        // Set a reward token before upgrade
        staking.addRewardToken(address(stakingToken));

        // Upgrade
        RewardsStakingV2 logicV2 = new RewardsStakingV2();
        staking.upgradeToAndCall(address(logicV2), "");

        // Make sure reward token still exists
        assertTrue(RewardsStakingV2(payable(address(staking))).isRewardToken(address(stakingToken)));

        vm.stopPrank();
    }
}