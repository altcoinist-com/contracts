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
        uint128 amount;
        uint32 startDaySinceDeployment;
        uint32 unlockDaySinceDeployment;
        uint32 cooldownStartDaySinceDeployment;
        LockType lockType;
    }

    struct UserData {
        uint32 lastClaimedDaySinceDeployment;
        uint32 positionCount;
    }

    IERC20 public immutable stakingToken;
    address[] public rewardTokens;
    mapping(address => uint8) public rewardTokenIndex; // index of token in rewardTokens array
    mapping(address => bool) public isRewardToken; // is token added as reward token

    uint256 constant COOLDOWN = 7;
    uint256 public constant DECAY_DAYS = 90;
    uint256 public constant DECAY_BASE = 990; // equivalent to 0.99 with scale 1000
    uint256 public constant DECAY_SCALE = 1000;
    uint256 public constant WEIGHT_SCALE = 1000;

    mapping(address => mapping(uint256 => StakingPosition)) public userPositions;
    mapping(address => UserData) public userData;

    // Delta-weight model
    mapping(address => mapping(uint256 => int256)) public userWeightDelta; // user => day => delta-weight
    mapping(uint256 => int256) public totalWeightDelta; // day => delta-weight

    // Emissions per reward token
    mapping(address => mapping(uint256 => uint256)) public emissionsByToken;  // rewardToken => day => amount

    uint256 public immutable deploymentDay;
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
        rewardTokenIndex[token] = uint8(rewardTokens.length);
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
            rewardTokenIndex[lastToken] = uint8(index);
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

        uint256 currentDay = getCurrentDaySinceDeployment();
        uint32 startDay = uint32(currentDay + 1); // staking starts from the next day
        uint32 unlockDay = lockType == LockType.LIQUID ? type(uint32).max : uint32(startDay + getLockDuration(lockType));

        UserData storage user = userData[msg.sender];
        uint256 positionIndex = user.positionCount++;

        userPositions[msg.sender][positionIndex] = StakingPosition({
            amount: uint128(amount),
            startDaySinceDeployment: startDay,
            unlockDaySinceDeployment: unlockDay,
            cooldownStartDaySinceDeployment: 0,
            lockType: lockType
        });

        uint256 weight = calculateWeight(amount, lockType);
        _updateWeightDelta(msg.sender, startDay, unlockDay, int256(weight));

        totalStaked += amount;
        
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, lockType, positionIndex);
    }

    function withdraw(uint256 index) external nonReentrant {
        StakingPosition storage pos = userPositions[msg.sender][index];
        if (pos.amount == 0) revert PositionNotExists();

        uint256 currentDaySinceDeployment = getCurrentDaySinceDeployment();
        
        if (pos.lockType == LockType.LIQUID) {
            if (pos.cooldownStartDaySinceDeployment == 0) {
                pos.cooldownStartDaySinceDeployment = uint32(currentDaySinceDeployment);
                emit CooldownInitiated(msg.sender, index);
                return;
            } else if (currentDaySinceDeployment < (uint256(pos.cooldownStartDaySinceDeployment) + COOLDOWN)) {
                revert CooldownNotFinished();
            }
        } else {
            if (currentDaySinceDeployment < pos.unlockDaySinceDeployment) revert PositionLocked();
        }

        _processWithdraw(msg.sender, index, pos, currentDaySinceDeployment);
    }

    function _processWithdraw(address user, uint256 index, StakingPosition storage pos, uint256 currentDay) internal {
        uint256 amount = pos.amount;
        if (amount == 0) revert InvalidAmount();

        uint256 weight = calculateWeight(amount, pos.lockType);
        _updateWeightDelta(user, currentDay, pos.unlockDaySinceDeployment, -int256(weight));

        totalStaked -= amount;
        
        pos.amount = 0;

        stakingToken.safeTransfer(user, amount);

        emit Withdrawn(user, amount, index);
    }

    function claim() external nonReentrant {
        uint256 rewardTokensLength = rewardTokens.length;
        if (rewardTokensLength == 0) revert EmptyRewardTokens();

        uint256 currentDaySinceDeployment = getCurrentDaySinceDeployment();
        UserData storage user = userData[msg.sender];
        uint32 lastClaimed = user.lastClaimedDaySinceDeployment;
        
        if (lastClaimed >= currentDaySinceDeployment) revert NothingToClaim();

        user.lastClaimedDaySinceDeployment = uint32(currentDaySinceDeployment);

        for (uint256 r = 0; r < rewardTokensLength; ) {
            address rewardToken = rewardTokens[r];
            uint256 totalReward = 0;
            
            int256 cumulativeUserWeight = 0;
            int256 cumulativeTotalWeight = 0;

            for (uint256 d = lastClaimed; d < currentDaySinceDeployment; ) {
                cumulativeUserWeight += userWeightDelta[msg.sender][d];
                cumulativeTotalWeight += totalWeightDelta[d];
                
                if (cumulativeUserWeight <= 0 || cumulativeTotalWeight <= 0) {
                    unchecked { ++d; }  
                    continue;
                }

                uint256 emissions = emissionsByToken[rewardToken][d];
                if (emissions > 0) {
                    uint256 userShare = (emissions * uint256(cumulativeUserWeight)) / uint256(cumulativeTotalWeight);
                    totalReward += userShare;
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

        uint256 currentDay = getCurrentDaySinceDeployment(); // emissions start from the current day
        
        // Pre-calculate decay weights to save gas
        (uint256[] memory decayWeightsByDay, uint256 totalDecayWeight) = _calculateDecayWeights();

        // Distribute emissions
        for (uint256 i = 0; i < DECAY_DAYS; ) {
            uint256 dailyAmount = (amount * decayWeightsByDay[i]) / totalDecayWeight;
            emissionsByToken[rewardToken][currentDay + i] += dailyAmount;
            unchecked { ++i; }
        }

        emit TopUp(rewardToken, amount);
    }

    function _calculateDecayWeights() internal pure returns (uint256[] memory decayWeightsByDay, uint256 totalWeight) {
        decayWeightsByDay = new uint256[](DECAY_DAYS);

        decayWeightsByDay[0] = DECAY_SCALE;
        totalWeight = DECAY_SCALE;

        for (uint256 i = 1; i < DECAY_DAYS; ) {
            decayWeightsByDay[i] = (decayWeightsByDay[i - 1] * DECAY_BASE) / DECAY_SCALE;
            totalWeight += decayWeightsByDay[i];
            unchecked { ++i; }
        }
    }

    function calculateWeight(uint256 amount, LockType lockType) internal pure returns (uint256) {
        return (amount * getLockMultiplier(lockType)) / WEIGHT_SCALE;
    }

    function _updateWeightDelta(address user, uint256 startDaySinceDeployment, uint256 endDaySinceDeployment, int256 delta) internal {
        userWeightDelta[user][startDaySinceDeployment] += delta;
        totalWeightDelta[startDaySinceDeployment] += delta;

        if (endDaySinceDeployment + 1 < type(uint256).max) {
            userWeightDelta[user][endDaySinceDeployment + 1] -= delta;
            totalWeightDelta[endDaySinceDeployment + 1] -= delta;
        }
    }

    function getCurrentDaySinceDeployment() public view returns (uint256) {
        uint256 currentTimestamp = block.timestamp / 1 days;
        if (currentTimestamp < deploymentDay) return 0;
        return currentTimestamp - deploymentDay;
    }

    function getLockDuration(LockType lt) internal pure returns (uint16) {
        if (lt == LockType.LIQUID) return 0;
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

    // ============ VIEW FUNCTIONS ============

    function getUserPositionCount(address user) external view returns (uint256) {
        return userData[user].positionCount;
    }

    function getUserPosition(address user, uint256 index) external view returns (StakingPosition memory) {
        return userPositions[user][index];
    }

    function getRewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    receive() external payable {
        revert("Contract does not accept ETH");
    }

    fallback() external payable {
        revert("Fallback function not allowed");
    }
}