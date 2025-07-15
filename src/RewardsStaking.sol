// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RewardsStaking is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum LockType { LIQUID, LOCK_1M, LOCK_3M, LOCK_6M, LOCK_12M }

    struct StakingPosition {
        uint256 amount;
        uint256 startTime;
        uint256 unlockTime;
        uint256 cooldownStart;
        LockType lockType;
    }

    IERC20 public immutable stakingToken;
    address[] public rewardTokens;
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

    event TopUp(address indexed token, uint256 amount);
    event Staked(address indexed user, uint256 amount, LockType lockType);
    event Withdrawn(address indexed user, uint256 amount);
    event Claimed(address indexed user, address indexed token, uint256 amount);

    constructor(IERC20 _stakingToken) {
        stakingToken = _stakingToken;
        deploymentDay = block.timestamp / 1 days;
    }

    function addRewardToken(address token) external {
        require(!isRewardToken[token], "Already added");
        isRewardToken[token] = true;
        rewardTokens.push(token);
    }

    function stake(uint256 amount, LockType lockType) external nonReentrant {
        require(amount > 0, "Cannot stake 0");

        uint256 lockPeriod = getLockDuration(lockType);
        uint256 unlockTime = block.timestamp + lockPeriod;

        userPositions[msg.sender].push(StakingPosition({
            amount: amount,
            startTime: block.timestamp,
            unlockTime: unlockTime,
            cooldownStart: 0,
            lockType: lockType
        }));

        uint256 day = block.timestamp / 1 days;
        uint256 weight = (amount * getLockMultiplier(lockType)) / WEIGHT_SCALE;
        userWeightPerDay[msg.sender][day] += weight;
        totalWeightPerDay[day] += weight;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, lockType);
    }

    function withdraw(uint256 index) external nonReentrant {
        StakingPosition[] storage positions = userPositions[msg.sender];
        require(index < positions.length, "Invalid index");

        StakingPosition memory pos = positions[index];
        if (pos.lockType == LockType.LIQUID) {
            require(pos.cooldownStart > 0 && block.timestamp >= pos.cooldownStart + COOLDOWN, "cooldown");
        } else {
            require(block.timestamp >= pos.unlockTime, "locked");
        }


        uint256 amount = pos.amount;
        require(amount > 0, "Nothing to withdraw");

        positions[index] = positions[positions.length - 1];
        positions.pop();

        uint256 day = block.timestamp / 1 days;
        uint256 weight = (amount * getLockMultiplier(pos.lockType)) / WEIGHT_SCALE;
        userWeightPerDay[msg.sender][day] -= weight;
        totalWeightPerDay[day] -= weight;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claim() external nonReentrant {
        uint256 currentDay = block.timestamp / 1 days - deploymentDay;
        uint256 last = lastClaimedDay[msg.sender];
        lastClaimedDay[msg.sender] = currentDay;

        for (uint256 r = 0; r < rewardTokens.length; r++) {
            address rewardToken = rewardTokens[r];
            uint256 totalReward;

            for (uint256 d = last; d < currentDay; d++) {
                uint256 totalWeight = totalWeightPerDay[d];
                if (totalWeight == 0) continue;

                uint256 userWeight = userWeightPerDay[msg.sender][d];
                if (userWeight == 0) continue;

                uint256 emissions = emissionsByToken[rewardToken][d];
                if (emissions == 0) continue;

                totalReward += (emissions * userWeight) / totalWeight;
            }

            if (totalReward > 0) {
                IERC20(rewardToken).safeTransfer(msg.sender, totalReward);
                emit Claimed(msg.sender, rewardToken, totalReward);
            }
        }
    }

    function topUp(address rewardToken, uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(isRewardToken[rewardToken], "Invalid reward token");
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentDay = block.timestamp / 1 days - deploymentDay;

        uint256[] memory emissions = new uint256[](DECAY_DAYS);
        uint256 totalWeight = 0;

        emissions[0] = DECAY_SCALE;
        totalWeight = DECAY_SCALE;

        for (uint256 i = 1; i < DECAY_DAYS; i++) {
            emissions[i] = (emissions[i - 1] * DECAY_BASE) / DECAY_SCALE;
            totalWeight += emissions[i];
        }

        for (uint256 i = 0; i < DECAY_DAYS; i++) {
            uint256 dailyAmount = (amount * emissions[i]) / totalWeight;
            emissionsByToken[rewardToken][currentDay + i] += dailyAmount;
        }

        emit TopUp(rewardToken, amount);
    }

    function getLockDuration(LockType lt) internal pure returns (uint256) {
        if (lt == LockType.LIQUID) return 0;
        if (lt == LockType.LOCK_1M) return 30 days;
        if (lt == LockType.LOCK_3M) return 90 days;
        if (lt == LockType.LOCK_6M) return 180 days;
        if (lt == LockType.LOCK_12M) return 365 days;
        revert("Invalid lock type");
    }

    function getLockMultiplier(LockType lt) internal pure returns (uint256) {
        if (lt == LockType.LIQUID) return 500;
        if (lt == LockType.LOCK_1M) return 550;
        if (lt == LockType.LOCK_3M) return 625;
        if (lt == LockType.LOCK_6M) return 750;
        if (lt == LockType.LOCK_12M) return 1000;
        revert("Invalid lock type");
    }
}
