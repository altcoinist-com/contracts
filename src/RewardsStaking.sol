// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RewardsStaking is ERC4626, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum LockType { LIQUID, LOCK_1M, LOCK_3M, LOCK_6M, LOCK_12M }

    struct Position {
        uint256 amount;
        uint256 startTime;
        uint256 unlockTime;
        LockType lockType;
    }

    IERC20 public immutable rewardALTT;
    IERC20 public immutable rewardATA;

    uint256 constant DECAY_DAYS = 90;
    uint256 public constant COOLDOWN = 7 days;

    mapping(address => Position[]) public userPositions;
    mapping(uint256 => uint256) public alttEmissionsByDay;
    mapping(uint256 => uint256) public ataEmissionsByDay;
    mapping(address => uint256) public lastClaimedDay;
    mapping(address => uint256) public pendingALTT;
    mapping(address => uint256) public pendingATA;

    uint256 public deploymentDay;

    event TopUp(address indexed token, uint256 amount);
    event Claimed(address indexed user, uint256 altt, uint256 ata);

    constructor(
        IERC20 _stakingToken,
        IERC20 _rewardALTT,
        IERC20 _rewardATA
    ) ERC20("Staked ALTT", "stALTT") ERC4626(_stakingToken) {
        rewardALTT = _rewardALTT;
        rewardATA = _rewardATA;
        deploymentDay = block.timestamp / 1 days;
    }

    function deposit(uint256 assets, address receiver, LockType lockType) external nonReentrant returns (uint256 shares) {
        require(assets > 0, "Zero amount");

        uint256 lockPeriod = getLockPeriod(lockType);
        uint256 unlock = block.timestamp + lockPeriod;

        Position memory p = Position({
            amount: assets,
            startTime: block.timestamp,
            unlockTime: unlock,
            lockType: lockType
        });

        userPositions[receiver].push(p);

        shares = previewDeposit(assets);
        _mint(receiver, shares);
        asset().safeTransferFrom(msg.sender, address(this), assets);
    }

    function withdraw(uint256 posIndex) external nonReentrant {
        Position memory p = userPositions[msg.sender][posIndex];
        require(p.amount > 0, "Invalid position");
        require(block.timestamp >= p.unlockTime, "Still locked");

        uint256 shares = previewWithdraw(p.amount);
        _burn(msg.sender, shares);
        asset().safeTransfer(msg.sender, p.amount);

        // Remove position
        Position[] storage positions = userPositions[msg.sender];
        positions[posIndex] = positions[positions.length - 1];
        positions.pop();
    }

    function topUp(IERC20 rewardToken, uint256 amount) external nonReentrant {
        require(rewardToken == rewardALTT || rewardToken == rewardATA, "Invalid token");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentDay = block.timestamp / 1 days - deploymentDay;
        uint256 remaining = amount;

        for (uint256 i = 0; i < DECAY_DAYS; i++) {
            uint256 day = currentDay + i;
            uint256 daily = remaining / (DECAY_DAYS - i);
            remaining -= daily;
            if (rewardToken == rewardALTT) alttEmissionsByDay[day] += daily;
            else ataEmissionsByDay[day] += daily;
        }

        emit TopUp(address(rewardToken), amount);
    }

    function claim() external nonReentrant {
        uint256 today = block.timestamp / 1 days - deploymentDay;
        uint256 last = lastClaimedDay[msg.sender];
        lastClaimedDay[msg.sender] = today;

        uint256 userWeight;
        for (uint256 i = 0; i < userPositions[msg.sender].length; i++) {
            Position memory p = userPositions[msg.sender][i];
            if (p.startTime + getLockPeriod(p.lockType) < block.timestamp) continue;
            userWeight += getWeight(p.lockType) * p.amount;
        }

        uint256 totalShares = totalSupply();
        require(totalShares > 0, "No active staking");

        for (uint256 d = last; d < today; d++) {
            uint256 dayAltt = alttEmissionsByDay[d];
            uint256 dayAta = ataEmissionsByDay[d];

            pendingALTT[msg.sender] += (dayAltt * userWeight) / totalShares;
            pendingATA[msg.sender] += (dayAta * userWeight) / totalShares;
        }

        uint256 toSendALTT = pendingALTT[msg.sender];
        uint256 toSendATA = pendingATA[msg.sender];

        if (toSendALTT > 0) {
            pendingALTT[msg.sender] = 0;
            rewardALTT.safeTransfer(msg.sender, toSendALTT);
        }

        if (toSendATA > 0) {
            pendingATA[msg.sender] = 0;
            rewardATA.safeTransfer(msg.sender, toSendATA);
        }

        emit Claimed(msg.sender, toSendALTT, toSendATA);
    }

    function getLockPeriod(LockType lt) internal pure returns (uint256) {
        if (lt == LockType.LIQUID) return 0;
        if (lt == LockType.LOCK_1M) return 30 days;
        if (lt == LockType.LOCK_3M) return 90 days;
        if (lt == LockType.LOCK_6M) return 180 days;
        if (lt == LockType.LOCK_12M) return 365 days;
        revert("Invalid lock type");
    }

    function getWeight(LockType lt) internal pure returns (uint256) {
        if (lt == LockType.LIQUID) return 50;
        if (lt == LockType.LOCK_1M) return 55;
        if (lt == LockType.LOCK_3M) return 62;
        if (lt == LockType.LOCK_6M) return 75;
        if (lt == LockType.LOCK_12M) return 100;
        return 0;
    }
}
