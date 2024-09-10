// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "v3-periphery/libraries/TransferHelper.sol";
import "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

interface Factory {
      function getPool(
    address tokenA,
    address tokenB,
    uint24 fee
  ) external view returns (address pool);
}
/// @custom:security-contact silur@cryptall.co
contract ALTT is ERC20, ERC20Permit, Ownable2Step {

    constructor(address initialOwner)
        ERC20("Altcoinist", "ALTT")
        ERC20Permit("Altcoinist")
        Ownable(initialOwner)
    {
        require(initialOwner != address(0));
    }

    function mint() public onlyOwner {
        _mint(msg.sender, 1e9 * 10**decimals());
        renounceOwnership();
    }

    function isAfterLP() public view returns (bool) {
    address pool = Factory(0x33128a8fC17869897dcE68Ed026d694621f6FDfD).getPool(
            0x4200000000000000000000000000000000000006,
            address(this),
            100
        );
        return (totalSupply() > 0 && pool != address(0));
    }
}
