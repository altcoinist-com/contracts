// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockTrustedForwarder
 * @dev Simplified trusted forwarder for testing ERC2771 functionality
 * This is a minimal implementation for testing purposes only
 */
contract MockTrustedForwarder {
    
    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
    }

    mapping(address => uint256) private _nonces;

    event MetaTransactionExecuted(address indexed from, address indexed to, bool success);

    function getNonce(address from) public view returns (uint256) {
        return _nonces[from];
    }

    /**
     * @dev Simple execute function for testing
     * In production, this would include signature verification
     */
    function executeWithoutSignature(ForwardRequest calldata req) external payable returns (bool success, bytes memory returndata) {
        _nonces[req.from]++;
        
        // Append the original sender to the call data for ERC2771
        bytes memory dataWithSender = abi.encodePacked(req.data, req.from);
        
        (success, returndata) = req.to.call{value: req.value, gas: req.gas}(dataWithSender);
        
        emit MetaTransactionExecuted(req.from, req.to, success);
    }

    /**
     * @dev Execute with manual sender override for testing
     */
    function executeAs(address originalSender, address target, bytes calldata data) external payable returns (bool success, bytes memory returndata) {
        _nonces[originalSender]++;
        
        // Append the original sender to the call data for ERC2771
        bytes memory dataWithSender = abi.encodePacked(data, originalSender);
        
        (success, returndata) = target.call{value: msg.value}(dataWithSender);
        
        emit MetaTransactionExecuted(originalSender, target, success);
    }
}
