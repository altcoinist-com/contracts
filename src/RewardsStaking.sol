// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract RewardsStaking is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    enum LockType { LIQUID, LOCK_1M, LOCK_3M, LOCK_6M, LOCK_12M }

    struct StakingPosition {
        uint96 amount;
        uint16 startDay;
        uint16 unlockDay;
        uint16 cooldownStartDay;
        LockType lockType;
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

    // delta-weight model
    mapping(address => mapping(uint256 => int256)) public userWeightDelta;
    mapping(uint256 => int256) public totalWeightDelta;

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

        uint256 currentDay = block.timestamp / 1 days;
        uint16 startDay = uint16(currentDay + 1); // activity starts from the next day
        uint16 unlockDay = uint16(startDay + getLockDuration(lockType));

        uint256 positionIndex = userPositions[msg.sender].length;
        userPositions[msg.sender].push(StakingPosition({
            amount: uint96(amount),
            startDay: startDay,
            unlockDay: unlockDay,
            cooldownStartDay: 0,
            lockType: lockType,
            exists: true
        }));

        uint256 weight = calculateWeight(amount, lockType);
        _updateWeightDelta(msg.sender, startDay, unlockDay, int256(weight));

        totalStaked += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, lockType, positionIndex);
    }

    function withdraw(uint256 index) external nonReentrant {
        StakingPosition[] storage positions = userPositions[msg.sender];
        if (index >= positions.length) revert InvalidIndex();

        StakingPosition storage pos = positions[index];
        if (!pos.exists) revert PositionNotExists();

        uint256 currentDay = block.timestamp / 1 days;
        if (pos.lockType == LockType.LIQUID) {
            if (pos.cooldownStartDay == 0) {
                pos.cooldownStartDay = uint16(currentDay);
                emit CooldownInitiated(msg.sender, index);
                return;
            } else if (block.timestamp < (uint256(pos.cooldownStartDay) * 1 days + COOLDOWN)) {
                revert CooldownNotFinished();
            }
        } else {
            if (currentDay < pos.unlockDay) revert PositionLocked();
        }

        uint256 amount = pos.amount;
        if (amount == 0) revert InvalidAmount();

        uint256 weight = calculateWeight(amount, pos.lockType);
        _updateWeightDelta(msg.sender, currentDay, pos.unlockDay, -int256(weight));

        totalStaked -= amount;
        pos.exists = false;
        pos.amount = 0;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, index);
    }

    function claim() external nonReentrant {
        if (rewardTokens.length == 0) revert EmptyRewardTokens();

        uint256 currentDay = getCurrentDay();
        uint256 lastClaimed = lastClaimedDay[msg.sender];
        if (lastClaimed >= currentDay) revert NothingToClaim();

        lastClaimedDay[msg.sender] = currentDay;

        for (uint256 r = 0; r < rewardTokens.length; ) {
            address rewardToken = rewardTokens[r];
            uint256 totalReward = 0;
            int256 userWeight = 0;
            int256 totalWeight = 0;

            for (uint256 d = lastClaimed; d < currentDay; ) {
                userWeight += userWeightDelta[msg.sender][d];
                totalWeight += totalWeightDelta[d];
                if (userWeight <= 0 || totalWeight <= 0) {
                    unchecked { ++d; }
                    continue;
                }

                uint256 emissions = emissionsByToken[rewardToken][d];
                if (emissions > 0) {
                    totalReward += (emissions * uint256(userWeight)) / uint256(totalWeight);
                }
                unchecked { ++d; }
            }

            if (totalReward > 0) {
                IERC20(rewardToken).safeTransfer(msg.sender, totalReward);
                emit Claimed(msg.sender, rewardToken, totalReward);
            }
            unchecked { ++r; }
        }
    }

    function topUp(address rewardToken, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (!isRewardToken[rewardToken]) revert InvalidRewardToken();

        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentDay = getCurrentDay(); // emissions start from the current day
        uint256[] memory emissions = new uint256[](DECAY_DAYS);
        emissions[0] = DECAY_SCALE;
        uint256 totalDecayWeight = DECAY_SCALE;

        for (uint256 i = 1; i < DECAY_DAYS; ) {
            emissions[i] = (emissions[i - 1] * DECAY_BASE) / DECAY_SCALE;
            totalDecayWeight += emissions[i];
            unchecked { ++i; }
        }

        for (uint256 i = 0; i < DECAY_DAYS; ) {
            uint256 dailyAmount = (amount * emissions[i]) / totalDecayWeight;
            emissionsByToken[rewardToken][currentDay + i] += dailyAmount;
            unchecked { ++i; }
        }

        emit TopUp(rewardToken, amount);
    }

    function calculateWeight(uint256 amount, LockType lockType) internal pure returns (uint256) {
        return (amount * getLockMultiplier(lockType)) / WEIGHT_SCALE;
    }

    function _updateWeightDelta(address user, uint256 startDay, uint256 endDay, int256 delta) internal {
        userWeightDelta[user][startDay] += delta;
        userWeightDelta[user][endDay + 1] -= delta;
        totalWeightDelta[startDay] += delta;
        totalWeightDelta[endDay + 1] -= delta;
    }

    function getCurrentDay() internal view returns (uint256) {
        uint256 currentTimestamp = block.timestamp / 1 days;
        return currentTimestamp >= deploymentDay ? currentTimestamp - deploymentDay : 0;
    }

    function getLockDuration(LockType lt) internal pure returns (uint16) {
        if (lt == LockType.LIQUID) return type(uint16).max;
        if (lt == LockType.LOCK_1M) return 30;
        if (lt == LockType.LOCK_3M) return 90;
        if (lt == LockType.LOCK_6M) return 180;
        if (lt == LockType.LOCK_12M) return 365;
        revert InvalidLockType();
    }

    function getLockMultiplier(LockType lt) internal pure returns (uint16) {
        if (lt == LockType.LIQUID) return 500;
        if (lt == LockType.LOCK_1M) return 550;
        if (lt == LockType.LOCK_3M) return 625;
        if (lt == LockType.LOCK_6M) return 750;
        if (lt == LockType.LOCK_12M) return 1000;
        revert InvalidLockType();
    }

    receive() external payable {
        revert("Contract does not accept ETH");
    }

    fallback() external payable {
        revert("Fallback function not allowed");
    }
}
