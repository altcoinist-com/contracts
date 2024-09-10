// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "./StakingFactory.sol";
import "./StakingVault.sol";
contract VaultNotifier {
    StakingFactory immutable factory;
    event WETHDeposit(address indexed vault, address indexed addr, uint256 amount);
    event WETHWithdraw(address indexed vault, address indexed addr, uint256 amount);
    event Deposit(address indexed vault, address indexed addr, uint256 amount);
    event Withdraw(address indexed vault, address indexed addr, uint256 amount);
    event PenalizedBoost(address indexed vault, address indexed owner, uint256 value);
    event TopupWeth(address indexed vault, uint256 vaule);
    constructor (address _factory) {
        factory = StakingFactory(_factory);
    }
    modifier onlyVault() {
        require(factory.vaults(StakingVault(msg.sender).creator()) == msg.sender, "PD");
        _;
    }
    function notifyDeposit(address vault, address addr, uint256 amount) public onlyVault {
        emit Deposit(vault, addr, amount);
    }
    function notifyWithdraw(address vault, address addr, uint256 amount) public onlyVault {
        emit Withdraw(vault, addr, amount);
    }
    function notifyWethDeposit(address vault, address addr, uint256 amount, uint256 wethAmount) public onlyVault {
        emit WETHDeposit(vault, addr, amount);
    }
    function notifyWethWithdraw(address vault, address addr, uint256 amount) public onlyVault {
        emit WETHWithdraw(vault, addr, amount);
    }
    function notifyPenalizedBoost(address vault, address addr, uint256 amount) public onlyVault {
        emit PenalizedBoost(vault, addr, amount);
    }
    function notifyTopupWeth(address vault, uint256 amount) public onlyVault {
        emit TopupWeth(vault, amount);
    }
}
