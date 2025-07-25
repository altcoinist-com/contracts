// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RewardsStaking} from "../../src/RewardsStaking.sol";
import {MockERC20} from "../../test/utils/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockTrustedForwarder} from "../../test/utils/MockTrustedForwarder.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RewardsStakingV2 is RewardsStaking {
    function version() external pure returns (string memory) {
        return "V2";
    }

    function newFunction() external pure returns (string memory) {
        return "Upgraded!";
    }

    function _authorizeUpgrade(address newImplementation) view internal override onlyOwner {}
}

contract RewardsStakingUpgradeTest is Test {
    RewardsStaking logic;
    RewardsStaking staking;
    ERC1967Proxy proxy;
    MockERC20 stakingToken;
    MockTrustedForwarder trustedForwarder; // mock trustedForwarder

    address deployer = address(0xABCD);

    function setUp() public {
    // 0. Set deployer as msg.sender
    vm.startPrank(deployer);

    // 1. Deploy mock token and trusted forwarder
    stakingToken = new MockERC20("Test Token", "TST", 18, 10_000_000 * 10**18);
    trustedForwarder = new MockTrustedForwarder();

    // 2. Deploy logic (implementation)
    logic = new RewardsStaking();

    // 3. Deploy proxy with initializer data
    bytes memory data = abi.encodeCall(
        RewardsStaking.initialize,
        (IERC20(address(stakingToken)), address(trustedForwarder))
    );
    proxy = new ERC1967Proxy(address(logic), data);

    // 4. Cast proxy to RewardsStaking
    staking = RewardsStaking(payable(address(proxy)));

    // 5. Call only-owner function
    staking.addRewardToken(address(stakingToken));

    vm.stopPrank();
}

    function test_InitialRewardTokensLength() public {
        assertEq(staking.getRewardTokensLength(), 1);
    }

    function test_UpgradeToV2AndCallNewFunction() public {
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

        // Upgrade
        RewardsStakingV2 logicV2 = new RewardsStakingV2();
        staking.upgradeToAndCall(address(logicV2), "");

        // Make sure reward token still exists
        assertEq(RewardsStakingV2(payable(address(staking))).getRewardTokensLength(), 1);

        vm.stopPrank();
    }
}