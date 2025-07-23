// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockForwarder {
    function verify(bytes calldata, bytes calldata) public pure returns (bool) {
        return true;
    }

    function execute(bytes calldata, bytes calldata) public payable returns (bool, bytes memory) {
        return (true, "");
    }
}