// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract RewardsStaking is
    Initializable,
    ContextUpgradeable,
    ReentrancyGuardUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    enum LockType { LIQUID, LOCK_1M, LOCK_3M, LOCK_6M, LOCK_12M }

    struct StakingPosition {
        uint128 amount;
        uint32 startDaySinceDeployment;
        uint32 unlockDaySinceDeployment;
        uint32 cooldownEndDaySinceDeployment;
        LockType lockType;
    }

    struct UserData {
        uint32 lastClaimedDaySinceDeployment;
        uint32 positionCount;
        int256 lastClaimedWeight;
        int256 lastClaimedTotalWeight;
    }

    IERC20 public stakingToken;
    address[] public rewardTokens;
    mapping(address => uint8) public rewardTokenIndex;
    mapping(address => bool) public isRewardToken;

    uint256 public constant COOLDOWN = 7;
    uint256 public constant DECAY_DAYS = 90;
    uint256 public constant DECAY_BASE = 990;
    uint256 public constant DECAY_SCALE = 1000;
    uint256 public constant WEIGHT_SCALE = 1000;
    uint256 public constant MIN_STAKING_AMOUNT = 100 * 10 ** 18;

    address[] public allStakers;
    mapping(address => UserData) public userData;
    mapping(address => mapping(uint256 => StakingPosition)) public userPositions;
    mapping(address => mapping(uint256 => int256)) public userWeightDelta;
    mapping(uint256 => int256) public totalWeightDelta;
    mapping(address => mapping(uint256 => uint256)) public emissionsByToken;

    uint256 public deploymentDay;
    uint256 public totalStaked;

    address private _trustedForwarder;

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
    error ZeroAddress();

    constructor() {
        _disableInitializers();
    }

    // === ADMIN INITIALIZER ===
    function initialize(IERC20 stakingToken_, address trustedForwarder_) external initializer {
        if (address(stakingToken_) == address(0)) revert ZeroAddress();
        if (trustedForwarder_ == address(0)) revert ZeroAddress();

        __Ownable_init(_msgSender());
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        stakingToken = stakingToken_;
        deploymentDay = block.timestamp / 1 days;
        _trustedForwarder = trustedForwarder_;
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

    function stake(uint256 amount, LockType lockType, bool autoClaim) external nonReentrant whenNotPaused {
        if (amount < MIN_STAKING_AMOUNT) revert InvalidAmount();

        address userAddress = _msgSender();
        uint256 currentDay = getCurrentDaySinceDeployment();
        uint32 startDay = uint32(currentDay + 1); // staking starts from the next day
        uint32 unlockDay = lockType == LockType.LIQUID ? type(uint32).max : uint32(startDay + getLockDuration(lockType));

        UserData storage user = userData[userAddress];
        if (user.positionCount == 0) {
            allStakers.push(userAddress);
        }

        uint256 positionIndex = user.positionCount++;

        userPositions[userAddress][positionIndex] = StakingPosition({
            amount: uint128(amount),
            startDaySinceDeployment: startDay,
            unlockDaySinceDeployment: unlockDay,
            cooldownEndDaySinceDeployment: 0,
            lockType: lockType
        });

        uint256 weight = calculateWeight(amount, lockType);
        _updateWeightDelta(userAddress, startDay, unlockDay, int256(weight));

        totalStaked += amount;

        stakingToken.safeTransferFrom(userAddress, address(this), amount);
        emit Staked(userAddress, amount, lockType, positionIndex);

        if (autoClaim) {
            _claim(userAddress);
        }
    }

    function withdraw(uint256 index, bool autoClaim) external nonReentrant {
        address userAddress = _msgSender();
        StakingPosition storage pos = userPositions[userAddress][index];
        uint256 amount = pos.amount;
        if (amount == 0) revert PositionNotExists();

        bool doClaim = false;
        uint256 currentDaySinceDeployment = getCurrentDaySinceDeployment();
        if (pos.lockType != LockType.LIQUID) {
            if (currentDaySinceDeployment < pos.unlockDaySinceDeployment) revert PositionLocked();

            uint256 weight = calculateWeight(amount, pos.lockType);
            _updateWeightDelta(userAddress, currentDaySinceDeployment, pos.unlockDaySinceDeployment, -int256(weight));

            _processWithdraw(userAddress, index, pos);
            doClaim = autoClaim;
        } else {
            // liquid staking
            if (pos.cooldownEndDaySinceDeployment == 0) {
                pos.cooldownEndDaySinceDeployment = uint32(currentDaySinceDeployment + COOLDOWN);

                uint256 weight = calculateWeight(amount, pos.lockType);
                _updateWeightDelta(userAddress, currentDaySinceDeployment, type(uint32).max, -int256(weight));

                emit CooldownInitiated(userAddress, index);
            } else {
                if (currentDaySinceDeployment < uint256(pos.cooldownEndDaySinceDeployment)) {
                    revert CooldownNotFinished();
                }

                _processWithdraw(userAddress, index, pos);
            }

            doClaim = autoClaim;
        }

        if (doClaim) {
            _claim(userAddress);
        }
    }

    function _processWithdraw(address userAddress, uint256 index, StakingPosition storage pos) internal {
        uint256 amount = pos.amount;

        totalStaked -= amount;
        pos.amount = 0;

        stakingToken.safeTransfer(userAddress, amount);

        emit Withdrawn(userAddress, amount, index);
    }

    function claim() external nonReentrant {
        _claim(_msgSender());
    }

    function _claim(address userAddress) internal {
        uint256 rewardTokensLength = rewardTokens.length;
        if (rewardTokensLength == 0) return;

        uint256 currentDaySinceDeployment = getCurrentDaySinceDeployment();
        UserData storage user = userData[userAddress];
        uint32 lastClaimed = user.lastClaimedDaySinceDeployment;

        if (lastClaimed >= currentDaySinceDeployment) return;

        user.lastClaimedDaySinceDeployment = uint32(currentDaySinceDeployment);
        int256 initUserWeight = user.lastClaimedWeight;
        int256 initTotalWeight = user.lastClaimedTotalWeight;
        
        for (uint256 r = 0; r < rewardTokensLength; ) {
            address rewardToken = rewardTokens[r];
            uint256 contractBalance = IERC20(rewardToken).balanceOf(address(this));
            if (contractBalance == 0) {
                unchecked { ++r; }
                continue;
            }

            uint256 totalReward = 0;
            int256 cumulativeUserWeight = initUserWeight;
            int256 cumulativeTotalWeight = initTotalWeight;
            for (uint256 d = lastClaimed; d < currentDaySinceDeployment; ) {
                cumulativeUserWeight += userWeightDelta[userAddress][d];
                cumulativeTotalWeight += totalWeightDelta[d];

                if (cumulativeUserWeight > 0 && cumulativeTotalWeight > 0) {
                    uint256 emissions = emissionsByToken[rewardToken][d];
                    if (emissions > 0) {
                        uint256 userShare = (emissions * uint256(cumulativeUserWeight)) / uint256(cumulativeTotalWeight);
                        totalReward += userShare;
                    }
                }

                unchecked { ++d; }
            }

            user.lastClaimedWeight = cumulativeUserWeight;
            user.lastClaimedTotalWeight = cumulativeTotalWeight;

            if (totalReward > 0) {
                IERC20(rewardToken).safeTransfer(userAddress, totalReward);
                emit Claimed(userAddress, rewardToken, totalReward);
            }

            unchecked { ++r; }
        }
    }

    function topUp(address rewardToken, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (!isRewardToken[rewardToken]) revert InvalidRewardToken();

        IERC20(rewardToken).safeTransferFrom(_msgSender(), address(this), amount);

        uint256 currentDay = getCurrentDaySinceDeployment(); // emissions start from the current day

        // Pre-calculate decay weights to save gas
        (uint256[] memory decayWeightsByDay, uint256 totalDecayWeight) = _calculateDecayWeights();

        // Distribute emissions
        uint256 totalDistributed;
        for (uint256 i = 0; i < DECAY_DAYS; ) {
            uint256 dailyAmount = (amount * decayWeightsByDay[i]) / totalDecayWeight;
            emissionsByToken[rewardToken][currentDay + i] += dailyAmount;
            totalDistributed += dailyAmount;
            unchecked { ++i; }
        }

        uint256 remainder = amount - totalDistributed;
        emissionsByToken[rewardToken][currentDay + DECAY_DAYS - 1] += remainder;

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

    function _updateWeightDelta(address user, uint256 startDay, uint256 endDay, int256 delta) internal {
        userWeightDelta[user][startDay] += delta;
        totalWeightDelta[startDay] += delta;

        if (endDay < type(uint256).max) {
            userWeightDelta[user][endDay] -= delta;
            totalWeightDelta[endDay] -= delta;
        }
    }

    function getCurrentDaySinceDeployment() public view returns (uint256) {
        uint256 currentTimestamp = block.timestamp / 1 days;
        return currentTimestamp < deploymentDay ? 0 : currentTimestamp - deploymentDay;
    }

    function getLockDuration(LockType lt) public pure returns (uint16) {
        if (lt == LockType.LIQUID) return 0;
        if (lt == LockType.LOCK_1M) return 30;
        if (lt == LockType.LOCK_3M) return 90;
        if (lt == LockType.LOCK_6M) return 180;
        if (lt == LockType.LOCK_12M) return 365;
        revert InvalidLockType();
    }

    function getLockMultiplier(LockType lt) public pure returns (uint16) {
        if (lt == LockType.LIQUID) return 500;
        if (lt == LockType.LOCK_1M) return 550;
        if (lt == LockType.LOCK_3M) return 625;
        if (lt == LockType.LOCK_6M) return 750;
        if (lt == LockType.LOCK_12M) return 1000;
        revert InvalidLockType();
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get the number of staking positions for a user
     * @param user Address of the user
     * @return count Number of staking positions
     */
    function getUserPositionCount(address user) external view returns (uint256) {
        return userData[user].positionCount;
    }

    /**
     * @notice Get a specific staking position for a user
     * @param user Address of the user
     * @param index Index of the position
     * @return position Staking position details
     */
    function getUserPosition(address user, uint256 index) external view returns (StakingPosition memory) {
        return userPositions[user][index];
    }

    /**
     * @notice Get the number of reward tokens configured
     * @return count Number of reward tokens
     */
    function getRewardTokensLength() external view returns (uint256) {
        return rewardTokens.length;
    }

    /**
     * @notice Get total number of stakers
     * @return Total number of unique stakers
     */
    function getStakersCount() external view returns (uint256) {
        return allStakers.length;
    }

    receive() external payable {
        revert("Contract does not accept ETH");
    }

    fallback() external payable {
        revert("Fallback function not allowed");
    }

    function _authorizeUpgrade(address newImplementation) view internal virtual override onlyOwner {
        if (newImplementation == address(0)) revert ZeroAddress();
    }

    // === ERC2771 implementation ===

    function trustedForwarder() public view returns (address) {
        return _trustedForwarder;
    }

    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder == _trustedForwarder;
    }

    function _msgSender() internal view virtual override returns (address) {
        uint256 calldataLength = msg.data.length;
        uint256 contextSuffixLength = _contextSuffixLength();
        if (calldataLength >= contextSuffixLength && isTrustedForwarder(msg.sender)) {
            unchecked {
                return address(bytes20(msg.data[calldataLength - contextSuffixLength:]));
            }
        } else {
            return super._msgSender();
        }
    }

    /**
     * @dev Override for `msg.data`. Defaults to the original `msg.data` whenever
     * a call is not performed by the trusted forwarder or the calldata length is less than
     * 20 bytes (an address length).
     */
    function _msgData() internal view virtual override returns (bytes calldata) {
        uint256 calldataLength = msg.data.length;
        uint256 contextSuffixLength = _contextSuffixLength();
        if (calldataLength >= contextSuffixLength && isTrustedForwarder(msg.sender)) {
            unchecked {
                return msg.data[:calldataLength - contextSuffixLength];
            }
        } else {
            return super._msgData();
        }
    }

    /**
     * @dev ERC-2771 specifies the context as being a single address (20 bytes).
     */
    function _contextSuffixLength() internal view virtual override returns (uint256) {
        return 20;
    }
}
