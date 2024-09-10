// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ALTT.sol";
import "../src/SubscribeRegistry.sol";
import "../src/StakingFactory.sol";
import "../src/StakingVault.sol";
import "../src/CreatorTokenFactory.sol";
import "../src/PaymentCollector.sol";
import "../src/TWAP.sol";
import "../src/XPRedeem.sol";
contract DeployAltt is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address xpSigner = vm.addr(vm.envUint("XP_SIGNER"));

        address admin = vm.addr(deployerPrivateKey);
	address adminGnosis = 0xA6c0CCb2ba30F94b490d5b20d75d1f5330a6d2a3;
        address ecosystem = 0xA6c0CCb2ba30F94b490d5b20d75d1f5330a6d2a3;

        vm.startBroadcast(deployerPrivateKey);

        // deploy contracts
        ALTT altt = new ALTT(adminGnosis);
        SubscribeRegistry registry = new SubscribeRegistry(address(altt), ecosystem);
        StakingVault vaultImpl = new StakingVault(IERC20(altt), registry);
        StakingFactory stakingFactory = new StakingFactory(address(registry), address(vaultImpl));
        CreatorTokenFactory creatorFactory = new CreatorTokenFactory(adminGnosis, address(registry));
        VaultNotifier notifier = new VaultNotifier(address(stakingFactory));
        TWAP twap = new TWAP(adminGnosis, address(altt), address(stakingFactory));
        registry.setFactories(address(stakingFactory), address(creatorFactory), address(notifier), address(twap));
        PaymentCollector collector = new PaymentCollector(adminGnosis, address(altt), address(registry));
        XPRedeem xpRedeem = new XPRedeem(address(altt), xpSigner);

        // hand over ownerships
        //altt.transferOwnership(adminGnosis);
        require(altt.owner() == adminGnosis);

	registry.transferOwnership(adminGnosis);
        require(registry.pendingOwner() == adminGnosis);

        stakingFactory.transferOwnership(adminGnosis);
        require(stakingFactory.owner() == adminGnosis);

        //twap.transferOwnership(adminGnosis);
        require(twap.owner() == adminGnosis);

        //creatorFactory.transferOwnership(adminGnosis);
        require(creatorFactory.owner() == adminGnosis);

        require(xpRedeem.offchainSigner() == xpSigner);
        vm.stopBroadcast();
        
        console.log("------------------------------------------");
	console.log("SubscribeRegistry: %s", address(registry));
        console.log("VaultImpl: %s", address(vaultImpl));
        console.log("StakingFactory: %s", address(stakingFactory));
        console.log("CreatorFactory: %s", address(creatorFactory));
        console.log("Notifier: %s", address(notifier));
        console.log("PaymentCollector: %s", address(collector));
        console.log("TWAP: %s", address(twap));
    }
}

