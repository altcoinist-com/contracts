// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "./SubscribeRegistry.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingFactory is ReentrancyGuard, Ownable {
    address public immutable impl;
    address public immutable registry;
    mapping (address => bool) nftWhitelist;
    mapping (address => address) public vaults;
    address public notifier;
    constructor (address _registry, address _impl)
    Ownable(msg.sender) {
        require(_registry != address(0));
        require(_impl != address(0));
        registry = _registry;
        impl = _impl;
    }

    function createPool(address creator) external nonReentrant returns (address) {
        require(msg.sender == registry, "PD");
        require(vaults[creator] == address(0));
        require(creator != address(0));
        address vault = Clones.clone(impl);
        vaults[creator] = vault;
        return vault;
    }

    function setWhitelist(address addr, bool val)
        external
        onlyOwner {
        require(addr != address(0));
        nftWhitelist[addr] = val;
    }


}
