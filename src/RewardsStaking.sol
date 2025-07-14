// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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

    struct Emission {
        address token;
        uint256 amount;
        uint256 startDay;
    }

    IERC20 public immutable stakingToken;
    address[] public rewardTokens;

    uint256 constant DECIMALS = 1e18;
    uint256 constant DECAY_DAYS = 90;
    uint256 constant COOLDOWN = 7 days;

    mapping(address => StakingPosition[]) public userPositions;
    mapping(address => uint256) public lastClaimedDay;
    mapping(address => mapping(uint256 => uint256)) public userWeightPerDay;
    mapping(uint256 => uint256) public totalWeightPerDay;
    mapping(address => mapping(address => uint256)) public pendingRewards;
    Emission[] public emissions;

    event Staked(address indexed user, uint256 amount, LockType lockType);
    event UnstakeRequested(address indexed user, uint256 index);
    event Withdrawn(address indexed user, uint256 amount);
    event Claimed(address indexed user, address rewardToken, uint256 amount);
    event TopUp(address indexed token, uint256 amount);

    constructor(IERC20 _stakingToken, address[] memory _rewardTokens)  {
        stakingToken = _stakingToken;
        rewardTokens = _rewardTokens;
    }

    function stake(uint256 amount, LockType lockType) external nonReentrant {
        require(amount > 0, "zero amount");
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 duration = getLockDuration(lockType);
        uint256 unlockTime = block.timestamp + duration;

        userPositions[msg.sender].push(StakingPosition({
            amount: amount,
            startTime: block.timestamp,
            unlockTime: unlockTime,
            cooldownStart: 0,
            lockType: lockType
        }));

        uint256 day = block.timestamp / 1 days;
        uint256 weight = (amount * getLockMultiplier(lockType)) / DECIMALS;
        userWeightPerDay[msg.sender][day] += weight;
        totalWeightPerDay[day] += weight;

        emit Staked(msg.sender, amount, lockType);
    }

    function requestUnstake(uint256 index) external {
        StakingPosition storage pos = userPositions[msg.sender][index];
        require(pos.amount > 0, "invalid position");
        if (pos.lockType == LockType.LIQUID) {
            pos.cooldownStart = block.timestamp;
        }
        emit UnstakeRequested(msg.sender, index);
    }

    function withdraw(uint256 index) external nonReentrant {
        StakingPosition storage pos = userPositions[msg.sender][index];
        require(pos.amount > 0, "invalid position");

        if (pos.lockType == LockType.LIQUID) {
            require(pos.cooldownStart > 0 && block.timestamp >= pos.cooldownStart + COOLDOWN, "cooldown");
        } else {
            require(block.timestamp >= pos.unlockTime, "locked");
        }

        uint256 amount = pos.amount;
        pos.amount = 0;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claim() external nonReentrant {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 fromDay = lastClaimedDay[msg.sender];
        lastClaimedDay[msg.sender] = currentDay;

        for (uint256 day = fromDay; day < currentDay; day++) {
            uint256 userWeight = userWeightPerDay[msg.sender][day];
            uint256 totalWeight = totalWeightPerDay[day];
            if (totalWeight == 0 || userWeight == 0) continue;

            for (uint256 i = 0; i < emissions.length; i++) {
                Emission memory e = emissions[i];
                if (day < e.startDay || day >= e.startDay + DECAY_DAYS) continue;
                uint256 emissionAmount = computeRecursiveEmission(e.amount, day - e.startDay);
                uint256 userShare = (emissionAmount * userWeight) / totalWeight;
                pendingRewards[msg.sender][e.token] += userShare;
            }
        }

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 amount = pendingRewards[msg.sender][token];
            if (amount > 0) {
                pendingRewards[msg.sender][token] = 0;
                IERC20(token).safeTransfer(msg.sender, amount);
                emit Claimed(msg.sender, token, amount);
            }
        }
    }

    function topUp(address rewardToken, uint256 amount) external {
        require(amount > 0, "zero");
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        emissions.push(Emission({ token: rewardToken, amount: amount, startDay: block.timestamp / 1 days }));
        emit TopUp(rewardToken, amount);
    }

    function computeRecursiveEmission(uint256 total, uint256 dayIndex) public pure returns (uint256) {
        uint256 remaining = total;
        uint256 emitted;
        for (uint256 i = 0; i <= dayIndex; i++) {
            uint256 today = remaining / DECAY_DAYS;
            emitted = today;
            remaining -= today;
        }
        return emitted;
    }

    function getLockDuration(LockType lt) public pure returns (uint256) {
        if (lt == LockType.LIQUID) return 0;
        if (lt == LockType.LOCK_1M) return 30 days;
        if (lt == LockType.LOCK_3M) return 90 days;
        if (lt == LockType.LOCK_6M) return 180 days;
        if (lt == LockType.LOCK_12M) return 365 days;
        revert("Invalid lock type");
    }

    function getLockMultiplier(LockType lt) public pure returns (uint256) {
        if (lt == LockType.LIQUID) return 0.5e18;
        if (lt == LockType.LOCK_1M) return 0.55e18;
        if (lt == LockType.LOCK_3M) return 0.625e18;
        if (lt == LockType.LOCK_6M) return 0.75e18;
        if (lt == LockType.LOCK_12M) return 1e18;
        revert("Invalid lock type");
    }
}
