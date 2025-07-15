// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract RewardsStaking is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    enum LockType { LIQUID, LOCK_1M, LOCK_3M, LOCK_6M, LOCK_12M }

    struct StakingPosition {
        uint256 amount;
        uint256 startTime;
        uint256 unlockTime;
        uint256 cooldownStart;
        LockType lockType;
        uint256 startDay;
        bool exists;
    }

    IERC20 public immutable stakingToken;
    address[] public rewardTokens;
    mapping(address => uint256) public rewardTokenIndex; // index of token in rewardTokens array
    mapping(address => bool) public isRewardToken;

    uint256 constant COOLDOWN = 7 days;
    uint256 public constant DECAY_DAYS = 90;
    uint256 public constant DECAY_BASE = 990; // equivalent to 0.99 with scale 1000
    uint256 public constant DECAY_SCALE = 1000;
    uint256 public constant WEIGHT_SCALE = 1000;

    mapping(address => StakingPosition[]) public userPositions;
    mapping(address => uint256) public lastClaimedDay;
    mapping(address => mapping(uint256 => uint256)) public userWeightPerDay;
    mapping(uint256 => uint256) public totalWeightPerDay;

    // Emissions and balances per reward token
    mapping(address => mapping(uint256 => uint256)) public emissionsByToken; // rewardToken => day => amount

    uint256 public deploymentDay;
    uint256 public totalStaked;

    // Events
    event TopUp(address indexed token, uint256 amount);
    event Staked(address indexed user, uint256 amount, LockType lockType, uint256 positionIndex);
    event Withdrawn(address indexed user, uint256 amount, uint256 positionIndex);
    event Claimed(address indexed user, address indexed token, uint256 amount);
    event CooldownInitiated(address indexed user, uint256 positionIndex);
    event RewardTokenAdded(address indexed token);
    event RewardTokenRemoved(address indexed token);

    error InvalidAmount();
    error InvalidIndex();
    error InvalidLockType();
    error InvalidRewardToken();
    error AlreadyAddedRewardToken();
    error CooldownNotInitiated();
    error CooldownNotFinished();
    error PositionLocked();
    error PositionNotExists();
    error NothingToClaim();
    error EmptyRewardTokens();
    error ZeroAddress();

    constructor(IERC20 _stakingToken) Ownable(msg.sender) {
        if (address(_stakingToken) == address(0)) revert ZeroAddress();
        stakingToken = _stakingToken;
        deploymentDay = block.timestamp / 1 days;
    }

    // ============ ADMIN FUNCTIONS ============

    function addRewardToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (isRewardToken[token]) revert AlreadyAddedRewardToken();
        
        isRewardToken[token] = true;
        rewardTokenIndex[token] = rewardTokens.length;
        rewardTokens.push(token);
        
        emit RewardTokenAdded(token);
    }

    function removeRewardToken(address token) external onlyOwner {
        if (!isRewardToken[token]) revert InvalidRewardToken();
        
        uint256 index = rewardTokenIndex[token];
        uint256 lastIndex = rewardTokens.length - 1;
        
        if (index != lastIndex) {
            address lastToken = rewardTokens[lastIndex];
            rewardTokens[index] = lastToken;
            rewardTokenIndex[lastToken] = index;
        }
        
        rewardTokens.pop();
        delete isRewardToken[token];
        delete rewardTokenIndex[token];
        
        emit RewardTokenRemoved(token);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ STAKING FUNCTIONS ============

    function stake(uint256 amount, LockType lockType) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        
        uint256 lockPeriod = getLockDuration(lockType);
        uint256 unlockTime = block.timestamp + lockPeriod;
        uint256 startDay = block.timestamp / 1 days;

        uint256 positionIndex = userPositions[msg.sender].length;
        
        userPositions[msg.sender].push(StakingPosition({
            amount: amount,
            startTime: block.timestamp,
            unlockTime: unlockTime,
            cooldownStart: 0,
            lockType: lockType,
            startDay: startDay,
            exists: true
        }));

        uint256 weight = (amount * getLockMultiplier(lockType)) / WEIGHT_SCALE;
        
        _updateWeightsForPeriod(msg.sender, startDay, unlockTime, weight, true);
        
        totalStaked += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, lockType, positionIndex);
    }

    function initiateCooldown(uint256 index) external nonReentrant {
        StakingPosition[] storage positions = userPositions[msg.sender];
        if (index >= positions.length) revert InvalidIndex();
        
        StakingPosition storage pos = positions[index];
        if (!pos.exists) revert PositionNotExists();
        if (pos.lockType != LockType.LIQUID) revert InvalidLockType();
        if (pos.cooldownStart != 0) revert(); // Cooldown уже инициирован
        
        pos.cooldownStart = block.timestamp;
        emit CooldownInitiated(msg.sender, index);
    }

    function withdraw(uint256 index) external nonReentrant {
        StakingPosition[] storage positions = userPositions[msg.sender];
        if (index >= positions.length) revert InvalidIndex();

        StakingPosition memory pos = positions[index];
        if (!pos.exists) revert PositionNotExists();
        
        if (pos.lockType == LockType.LIQUID) {
            if (pos.cooldownStart == 0) revert CooldownNotInitiated();
            if (block.timestamp < pos.cooldownStart + COOLDOWN) revert CooldownNotFinished();
        } else {
            if (block.timestamp < pos.unlockTime) revert PositionLocked();
        }

        uint256 amount = pos.amount;
        if (amount == 0) revert InvalidAmount();

        // mark position as non existing
        positions[index].exists = false;
        positions[index].amount = 0;

        // update weights - remove weight from current day to end of lock
        uint256 currentDay = block.timestamp / 1 days;
        uint256 weight = (amount * getLockMultiplier(pos.lockType)) / WEIGHT_SCALE;
        _updateWeightsForPeriod(msg.sender, currentDay, pos.unlockTime, weight, false);

        totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, index);
    }

    // ============ REWARDS FUNCTIONS ============

    function claim() external nonReentrant {
        if (rewardTokens.length == 0) revert EmptyRewardTokens();
        
        uint256 currentDay = getCurrentDay();
        uint256 lastClaimed = lastClaimedDay[msg.sender];
        
        if (lastClaimed >= currentDay) revert NothingToClaim();
        
        lastClaimedDay[msg.sender] = currentDay;

        bool hasRewards = false;
        
        for (uint256 r = 0; r < rewardTokens.length; r++) {
            address rewardToken = rewardTokens[r];
            uint256 totalReward = 0;

            for (uint256 d = lastClaimed; d < currentDay; d++) {
                uint256 totalWeight = totalWeightPerDay[d];
                if (totalWeight == 0) continue;

                uint256 userWeight = userWeightPerDay[msg.sender][d];
                if (userWeight == 0) continue;

                uint256 emissions = emissionsByToken[rewardToken][d];
                if (emissions == 0) continue;

                totalReward += (emissions * userWeight) / totalWeight;
            }

            if (totalReward > 0) {
                hasRewards = true;
                IERC20(rewardToken).safeTransfer(msg.sender, totalReward);
                emit Claimed(msg.sender, rewardToken, totalReward);
            }
        }
        
        if (!hasRewards) revert NothingToClaim();
    }

    function topUp(address rewardToken, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (!isRewardToken[rewardToken]) revert InvalidRewardToken();
        
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentDay = getCurrentDay();
        uint256[] memory emissions = new uint256[](DECAY_DAYS);
        uint256 totalWeight = 0;

        emissions[0] = DECAY_SCALE;
        totalWeight = DECAY_SCALE;

        for (uint256 i = 1; i < DECAY_DAYS; i++) {
            emissions[i] = (emissions[i - 1] * DECAY_BASE) / DECAY_SCALE;
            totalWeight += emissions[i];
        }

        // distribute rewards by days
        for (uint256 i = 0; i < DECAY_DAYS; i++) {
            uint256 dailyAmount = (amount * emissions[i]) / totalWeight;
            emissionsByToken[rewardToken][currentDay + i] += dailyAmount;
        }

        emit TopUp(rewardToken, amount);
    }

    // ============ INTERNAL FUNCTIONS ============

    function _updateWeightsForPeriod(
        address user,
        uint256 startDay,
        uint256 unlockTime,
        uint256 weight,
        bool isAdding
    ) internal {
        uint256 endDay = unlockTime / 1 days;
        
        for (uint256 day = startDay; day <= endDay; day++) {
            if (isAdding) {
                userWeightPerDay[user][day] += weight;
                totalWeightPerDay[day] += weight;
            } else {
                userWeightPerDay[user][day] -= weight;
                totalWeightPerDay[day] -= weight;
            }
        }
    }

    function getCurrentDay() internal view returns (uint256) {
        uint256 currentTimestamp = block.timestamp / 1 days;
        return currentTimestamp >= deploymentDay ? currentTimestamp - deploymentDay : 0;
    }

    function getLockDuration(LockType lt) internal pure returns (uint256) {
        if (lt == LockType.LIQUID) return 0;
        if (lt == LockType.LOCK_1M) return 30 days;
        if (lt == LockType.LOCK_3M) return 90 days;
        if (lt == LockType.LOCK_6M) return 180 days;
        if (lt == LockType.LOCK_12M) return 365 days;
        revert InvalidLockType();
    }

    function getLockMultiplier(LockType lt) internal pure returns (uint256) {
        if (lt == LockType.LIQUID) return 500;
        if (lt == LockType.LOCK_1M) return 550;
        if (lt == LockType.LOCK_3M) return 625;
        if (lt == LockType.LOCK_6M) return 750;
        if (lt == LockType.LOCK_12M) return 1000;
        revert InvalidLockType();
    }

    // ============ VIEW FUNCTIONS ============

    function getUserPositions(address user) external view returns (StakingPosition[] memory) {
        return userPositions[user];
    }

    function getUserPositionCount(address user) external view returns (uint256) {
        return userPositions[user].length;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function getRewardTokensCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    function getPendingRewards(address user) external view returns (address[] memory tokens, uint256[] memory amounts) {
        uint256 tokenCount = rewardTokens.length;
        tokens = new address[](tokenCount);
        amounts = new uint256[](tokenCount);
        
        uint256 currentDay = getCurrentDay();
        uint256 lastClaimed = lastClaimedDay[user];
        
        for (uint256 r = 0; r < tokenCount; r++) {
            address rewardToken = rewardTokens[r];
            tokens[r] = rewardToken;
            
            uint256 totalReward = 0;
            for (uint256 d = lastClaimed; d < currentDay; d++) {
                uint256 totalWeight = totalWeightPerDay[d];
                if (totalWeight == 0) continue;

                uint256 userWeight = userWeightPerDay[user][d];
                if (userWeight == 0) continue;

                uint256 emissions = emissionsByToken[rewardToken][d];
                if (emissions == 0) continue;

                totalReward += (emissions * userWeight) / totalWeight;
            }
            
            amounts[r] = totalReward;
        }
    }

    function getUserWeight(address user, uint256 day) external view returns (uint256) {
        return userWeightPerDay[user][day];
    }

    function getTotalWeight(uint256 day) external view returns (uint256) {
        return totalWeightPerDay[day];
    }

    function getEmissions(address rewardToken, uint256 day) external view returns (uint256) {
        return emissionsByToken[rewardToken][day];
    }

    function canWithdraw(address user, uint256 index) external view returns (bool) {
        StakingPosition[] storage positions = userPositions[user];
        if (index >= positions.length) return false;
        
        StakingPosition memory pos = positions[index];
        if (!pos.exists) return false;
        
        if (pos.lockType == LockType.LIQUID) {
            return pos.cooldownStart > 0 && block.timestamp >= pos.cooldownStart + COOLDOWN;
        } else {
            return block.timestamp >= pos.unlockTime;
        }
    }

    function timeUntilUnlock(address user, uint256 index) external view returns (uint256) {
        StakingPosition[] storage positions = userPositions[user];
        if (index >= positions.length) return 0;
        
        StakingPosition memory pos = positions[index];
        if (!pos.exists) return 0;
        
        uint256 unlockTime;
        if (pos.lockType == LockType.LIQUID) {
            if (pos.cooldownStart == 0) return type(uint256).max;
            unlockTime = pos.cooldownStart + COOLDOWN;
        } else {
            unlockTime = pos.unlockTime;
        }
        
        return unlockTime > block.timestamp ? unlockTime - block.timestamp : 0;
    }
}