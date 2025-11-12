// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SubscriptionPayment
 * @notice Ultra-simple payment distributor for subscriptions
 * @dev NO storage (except immutable token), NO logic - everything calculated off-chain
 * 
 * Backend calculates everything:
 * - Who gets paid (creator, ecosystem, team, referrer, etc.)
 * - How much each address receives
 * - Bonus months
 * - All percentages
 * 
 * Contract just:
 * 1. Validates creator is in recipients list
 * 2. Validates sum of amounts equals total
 * 3. Transfers funds
 * 4. Emits event
 * 
 * Example call from backend:
 * ```
 * // User buys 6 months @ 0.1 ETH = 0.6 ETH
 * // Backend calculated bonus: +1 month
 * // Backend calculated split: 72% / 16% / 12%
 * 
 * processSubscription(
 *   subscriber,          // user wallet
 *   creator,             // creator wallet (must be in recipients!)
 *   6,                   // purchased months
 *   7,                   // total months (6 + 1 bonus)
 *   [creator, ecosystem, team],  // recipients
 *   [432000000000000000,         // 0.432 ETH to creator
 *    96000000000000000,          // 0.096 ETH to ecosystem  
 *    72000000000000000]          // 0.072 ETH to team
 * )
 * ```
 */
contract SubscriptionPayment is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Payment token (WETH on Base: 0x4200000000000000000000000000000000000006)
    IERC20 public immutable paymentToken;
    
    /**
     * @notice Emitted when subscription payment is processed
     * @param subscriber User who paid
     * @param creator Creator who receives subscription
     * @param purchasedMonths Months user paid for
     * @param totalMonths Total months granted (with bonuses)
     * @param recipients All addresses that received funds
     * @param amounts Amounts sent to each recipient
     * @param totalAmount Total amount distributed
     * @param timestamp Block timestamp
     */
    event SubscriptionProcessed(
        address indexed subscriber,
        address indexed creator,
        uint256 purchasedMonths,
        uint256 totalMonths,
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
     * @dev All calculations done off-chain, contract only validates and executes
     * 
     * @param subscriber User paying for subscription
     * @param creator Creator receiving subscription (must be in recipients array)
     * @param purchasedMonths Number of months user paid for
     * @param totalMonths Total months granted (purchased + bonus calculated by backend)
     * @param recipients Array of addresses to receive funds
     * @param amounts Array of amounts for each recipient (must sum to total)
     * 
     * Requirements:
     * - recipients and amounts arrays must have same length
     * - creator must be in recipients array
     * - sum of amounts must equal total amount transferred
     * - subscriber cannot be creator or in recipients
     */
    function processSubscription(
        address subscriber,
        address creator,
        uint256 purchasedMonths,
        uint256 totalMonths,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant {
        // Basic validation
        require(subscriber != address(0), "Invalid subscriber");
        require(creator != address(0), "Invalid creator");
        require(purchasedMonths > 0, "Invalid months");
        require(totalMonths >= purchasedMonths, "Invalid total months");
        require(recipients.length > 0, "No recipients");
        require(recipients.length == amounts.length, "Length mismatch");
        require(subscriber != creator, "Cannot self-subscribe");
        
        // Validate creator is in recipients list
        bool creatorFound = false;
        for (uint i = 0; i < recipients.length; i++) {
            if (recipients[i] == creator) {
                creatorFound = true;
            }
            require(recipients[i] != address(0), "Invalid recipient");
            require(recipients[i] != subscriber, "Subscriber in recipients");
        }
        require(creatorFound, "Creator not in recipients");
        
        // Calculate total amount
        uint256 totalAmount = 0;
        for (uint i = 0; i < amounts.length; i++) {
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
            creator,
            purchasedMonths,
            totalMonths,
            recipients,
            amounts,
            totalAmount,
            block.timestamp
        );
    }
}
