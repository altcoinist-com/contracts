// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FeeDistributor
 * @dev A minimal contract that distributes ETH to multiple recipients
 * @notice This contract accepts ETH and distributes it to specified recipients
 */
contract FeeDistributor {
    /// @dev Emitted when ETH is distributed to recipients
    event ETHDistributed(
        address[] recipients,
        uint256[] amounts,
        uint256 totalAmount
    );

    /**
     * @dev Distributes ETH to multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to send to each recipient
     */
    function distribute(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable {
        require(recipients.length == amounts.length, "ARRAY_LENGTH_MISMATCH");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        require(msg.value == totalAmount, "VALUE_MISMATCH");

        for (uint256 i = 0; i < recipients.length; i++) {
            (bool success, ) = recipients[i].call{value: amounts[i]}("");
            require(success, "TRANSFER_FAILED");
        }

        emit ETHDistributed(recipients, amounts, totalAmount);
    }
}
