// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

contract CreatorTokenFactory is ERC1155, Ownable2Step, ERC1155Supply {
    address public immutable registry;
    mapping (address => bool) whitelist;
    mapping (address => bool) mintWhitelist;
    mapping (uint256 => mapping (address => uint8)) transferWhitelist;
    constructor(address initialOwner, address _registry)
        ERC1155("https://altcoinist.com/api/erc1155/")
        Ownable(initialOwner) {
        registry = _registry;
        mintWhitelist[_registry]  = true;
    }

    function mint(address account, uint256 id, uint256 amount, bytes memory data)
        public
    {
        require(msg.sender == owner() || mintWhitelist[msg.sender], "PD");
        _mint(account, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        public
    {
        require(msg.sender == owner() || mintWhitelist[msg.sender], "PD");
        _mintBatch(to, ids, amounts, data);
    }

    function setMintWhitelist(address addr, bool val)
        public
        onlyOwner {
        require(addr != address(0) && addr != registry);
        mintWhitelist[addr] = val;
    }
    function setTransferWhitelist(uint256 id, address addr, uint8 val)
        public
        onlyOwner {
        require(addr != address(0));
        transferWhitelist[id][addr] = val;
    }
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Supply) {
        require(ids.length == values.length);
        bool allowed = true;
        for(uint256 i=0; i<ids.length; i++) {
            uint256 id = ids[i];
            allowed = allowed && (
                from == address(0) ||
                transferWhitelist[id][from] == 1 || transferWhitelist[id][to] == 2 ||
                transferWhitelist[id][from] == 3 || transferWhitelist[id][to] == 3
            );
        }
        require(allowed, "soulbound");
        super._update(from, to, ids, values);
    }
}
