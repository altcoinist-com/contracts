// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SubscriptionPayment
 * @notice Ultra-minimal subscription payment distributor
 * @dev NO storage (except immutable token), NO logic - everything calculated off-chain
 * 
 * Optimized version:
 * - Removed `creator` field (redundant - creator is in recipients)
 * - Single `months` field instead of purchasedMonths/totalMonths
 * - Using `amounts` not percentages (better precision, minimal gas difference)
 * 
 * Backend does ALL calculations:
 * - Bonuses (6 months → +1 bonus = 7 total)
 * - Distribution (72% creator, 16% ecosystem, 12% team)
 * - Referrals
 * - Everything else
 * 
 * Contract only:
 * 1. Validates arrays match
 * 2. Transfers funds
 * 3. Emits event
 * 
 * Example:
 * ```
 * // User buys 6 months @ 0.1 ETH = 0.6 ETH
 * // Backend calculates: +1 bonus = 7 months total
 * // Backend calculates split: 72% / 16% / 12%
 * 
 * processSubscription(
 *   user,                              // who pays
 *   7,                                 // months (with bonuses from backend)
 *   [creator, ecosystem, team],        // who receives
 *   [0.432 ETH, 0.096 ETH, 0.072 ETH] // how much each
 * )
 * ```
 */
contract SubscriptionPayment is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Payment token (WETH on Base: 0x4200000000000000000000000000000000000006)
    IERC20 public immutable paymentToken;
    
    /**
     * @notice Emitted when subscription payment is processed
     * @param subscriber User who paid for subscription
     * @param months Total months granted (including bonuses calculated by backend)
     * @param recipients Addresses that received funds
     * @param amounts Amounts sent to each recipient
     * @param totalAmount Total amount distributed
     * @param timestamp Block timestamp
     */
    event SubscriptionProcessed(
        address indexed subscriber,
        uint256 months,
        address[] recipients,
        uint256[] amounts,
        uint256 totalAmount,
        uint256 timestamp
    );
    
    constructor(address _paymentToken) {
        require(_paymentToken != address(0), "Invalid token");
        paymentToken = IERC20(_paymentToken);
    }
    
    /**
     * @notice Process subscription payment - distribute funds to multiple recipients
     * @dev All calculations done off-chain by backend
     * 
     * @param subscriber User paying for subscription
     * @param months Total months of subscription (including bonuses from backend)
     * @param recipients Addresses to receive funds (must include creator)
     * @param amounts Amounts for each recipient (must sum to total)
     * 
     * Requirements:
     * - Arrays must have same length and be non-empty
     * - Sum of amounts must equal total transferred
     * - No recipient can be subscriber
     * - All recipients must be valid addresses
     */
    function processSubscription(
        address subscriber,
        uint256 months,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant {
        // Basic validation
        require(subscriber != address(0), "Invalid subscriber");
        require(months > 0, "Invalid months");
        require(recipients.length > 0, "No recipients");
        require(recipients.length == amounts.length, "Length mismatch");
        
        // Calculate total and validate recipients
        uint256 totalAmount = 0;
        for (uint i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(recipients[i] != subscriber, "Subscriber in recipients");
            require(amounts[i] > 0, "Invalid amount");
            totalAmount += amounts[i];
        }
        
        // Transfer total from subscriber to contract
        paymentToken.safeTransferFrom(subscriber, address(this), totalAmount);
        
        // Distribute to all recipients
        for (uint i = 0; i < recipients.length; i++) {
            paymentToken.safeTransfer(recipients[i], amounts[i]);
        }
        
        // Emit event for backend monitoring
        emit SubscriptionProcessed(
            subscriber,
            months,
            recipients,
            amounts,
            totalAmount,
            block.timestamp
        );
    }
}
