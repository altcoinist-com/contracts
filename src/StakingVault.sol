// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ALTT.sol";
import "./SubscribeRegistry.sol";
import "./StakingFactory.sol";
import "./CreatorTokenFactory.sol";
import "./Notifier.sol";
import "./TWAP.sol";

contract StakingVault is ERC4626, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    string private lName;
    string private lSymbol;
    address public creator;
    IERC20 immutable weth;
    IV3SwapRouter immutable swapRouter;
    StakingFactory stakingFactory;
    CreatorTokenFactory creatorTokenFactory;
    VaultNotifier notifier;
    SubscribeRegistry public immutable registry;
    TWAP public twap;
    uint256 public start;
    mapping (address => bool) public boostLost;

    struct UserDeposit {
        uint256 timestamp;
        uint256 amount;
    }
    mapping (address => uint256) public wethDeposits;
    mapping (address => uint256) public deposits;
    mapping (address => UserDeposit) public lastDeposit;
    uint256 public wethDepositSum;
    bool conversionDone;
    bool lockSwap;
    bool lockDeposit;
    address self;

    modifier afterLP() {
        require(ALTT(asset()).isAfterLP(), "TGEE");
        _;
    }

    constructor(IERC20 _altt, SubscribeRegistry _registry)
        ERC20("", "")
        ERC4626(_altt) // duplicate due to IR compilation
    {
        require(address(_altt) != address(0) && address(_registry) != address(0));
        wethDepositSum = 0;
        conversionDone = false;
        weth = IERC20(0x4200000000000000000000000000000000000006);
        swapRouter = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481); // mainnet
        //swapRouter = IV3SwapRouter(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4); // sepolia
        lockSwap = false;
        lockDeposit = false;
        registry = _registry;
    }

    event VaultInitialized(address indexed vault, address indexed creator);
    function init(
        address _self,
        address _creator,
        string memory _name,
        address _stakingFactory,
        address _creatorTokenFactory,
        address _notifier,
        address _twap
    )
        external
        nonReentrant {
        require(_self != address(0));
        require(_msgSender() == address(registry), "PD");
        require(_stakingFactory != address(0) &&
               _creatorTokenFactory != address(0));
        require(bytes(lName).length == 0 && bytes(lSymbol).length == 0);
        require(_creator != address(0));
        creator = _creator;
        lName = string.concat(_name, " ALTT staking pool");
        lSymbol = string.concat("stALTT ", _name);
        self = _self;
        stakingFactory = StakingFactory(_stakingFactory);
        creatorTokenFactory = CreatorTokenFactory(_creatorTokenFactory);
        notifier = VaultNotifier(_notifier);
        twap = TWAP(_twap);
        start = block.timestamp;
        emit VaultInitialized(self, _creator);
    }


    function name() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return lName;
    }

    function symbol() public view override(ERC20, IERC20Metadata) returns (string memory) {
        return lSymbol;
    }


    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
         internal
         afterLP
         override(ERC4626) {
         require(!lockDeposit, "deposit locked");
         lockDeposit = true;
         require(creator != address(0), "UI");
         require(creatorTokenFactory.balanceOf(receiver, uint256(uint160(creator))) > 0 || _msgSender() == creator, "PD");
         require(registry.getSubDetails(creator, receiver) >= block.timestamp || _msgSender() == address(registry) || _msgSender() == creator, "IS");
         uint256 daysSinceStart = Math.min(1 + (block.timestamp - start)/(1 days), 599);
         uint256 daysSinceLastDeposit = 0;
         if (lastDeposit[receiver].timestamp > 0) {
            daysSinceLastDeposit = Math.min(1 + (block.timestamp - lastDeposit[receiver].timestamp)/(1 days), 599);
         }

         uint256 refund = unlockedRewards(receiver); // in assets
         if (refund > 0) {
             // to accomodate for past slashes
             // note that this ONLY works because the pool token is soulbound,
             // otherwise the balance can be less than the share converted refund
             // by simply transferring tokens between wallets
             uint256 sharesToBurn = Math.min(balanceOf(receiver), _convertToShares(refund, Math.Rounding.Ceil));
             //super._burn(receiver, sharesToBurn);
             if (caller == address(registry) || caller == self) {
                 super._withdraw(receiver, receiver, receiver, refund, sharesToBurn);
             } else {
                 super._withdraw(caller, receiver, caller, refund, sharesToBurn);
             }
             //require(balanceOf(receiver) == 0, "refund");
             //deposits[receiver] = 0;
         }

         //uint256 penaltyStart = lastDeposit[receiver] > 0 ? daysSinceLastDeposit : 0;
         shares = assets;
         uint256 r = assets;
         uint256 i=0;
         
         for(; i<daysSinceLastDeposit; i++) {
             r = (r*9965)/10000;
         }

         for(i=0; i<daysSinceStart; i++) {
             shares = (shares*9965)/10000;
         }

         if (daysSinceLastDeposit > 0 && !boostLost[receiver]) {
             shares += (assets - r);
         }

         // we don't apply boost from the start,
         // only the period between the last deposit
         // and now.

         
         assert(shares <= assets);
         if (caller != self) {
             SafeERC20.safeTransferFrom(IERC20(asset()), caller, self, assets);
         }
         _mint(receiver, shares);
         deposits[receiver] += assets;

         lastDeposit[receiver] = UserDeposit(block.timestamp, assets);
         boostLost[receiver] = false;
         //lastDeposit[receiver].timestamp = block.timestamp;
         lockDeposit = false;

         notifier.notifyDeposit(creator, receiver, assets);
     }

     function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
         internal
         nonReentrant
         afterLP
         override(ERC4626) {

         bool lboostLost = assets > unlockedRewards(owner);
         if (lboostLost) {
             deposits[owner] -= Math.min(assets, deposits[owner]);
         }

         super._withdraw(caller, receiver, owner, assets, shares);

         // a second check is needed as _whitdraw uses an unadjusted deposit amount
         if (lboostLost) {
             uint256 amountToSlash = balanceOf(owner);
             uint256 daysSinceStart = Math.min(1 + (block.timestamp - start)/(1 days), 599);
             for(uint256 i=0; i<daysSinceStart; i++) {
                 amountToSlash = (amountToSlash * 9965)/10000;
             }
             assert(balanceOf(owner) >= amountToSlash);
             _burn(owner, balanceOf(owner) - amountToSlash);
         }
         notifier.notifyWithdraw(creator, owner, assets);
     }

     // in assets
     function maxWithdraw(address owner)
         public
         view
         override(ERC4626)
         returns (uint256) {
         // uint256 deposit = lastDeposit[owner].amount;
         uint256 deposit = deposits[owner];
         return deposit + unlockedRewards(owner);
     }

     function maxRedeem(address owner)
         public
         view
         override(ERC4626)
         returns (uint256) {
         return Math.min(balanceOf(owner), _convertToShares(maxWithdraw(owner), Math.Rounding.Ceil));
     }




     /// @notice users can deposit WETH prior ALTT TGE
     /// which doesn't have any yield. After TGE users
     /// can freely remove this WETH and the project has
     /// no power over it. It only serves as an initial
     /// metric for TVL before TGE
     function depositWeth(address receiver, uint256 amount) public nonReentrant returns (uint256) {
         require(receiver != address(0) && amount > 0, "IP");
         if (receiver != _msgSender() && _msgSender() != address(registry) && receiver != self) {
             revert("cannot deposit for else");
         }
         require(creatorTokenFactory.balanceOf(receiver, uint256(uint160(creator))) > 0 ||
                 _msgSender() == address(registry) ||
                 _msgSender() == creator
                 , "PD");

         weth.safeTransferFrom(_msgSender(), self, amount);
         // before LP pool
         if (!ALTT(asset()).isAfterLP()) {
             // we are generating yield from subs, not direct WETH staking
             if (receiver != self) {
                 wethDepositSum += amount;
                 wethDeposits[receiver] += amount;
             }
             notifier.notifyWethDeposit(creator, receiver, amount, amount);
             return amount;
         } else {
             // after TGE+LP
             uint256 amountOut = swapWethForAltt(amount);
             _deposit(self, receiver, amountOut, amountOut);
             notifier.notifyWethDeposit(creator, receiver, amount, amountOut);
             return amountOut;
         }
     }

     function withdrawWeth(uint256 amount) public nonReentrant {
         require(getWethDeposit(_msgSender()) >= amount && wethDepositSum >= amount, "IB");
         weth.safeTransfer(_msgSender(), amount);
         wethDeposits[_msgSender()] -= amount;
         wethDepositSum -= amount;
         notifier.notifyWethWithdraw(creator, _msgSender(), amount);
     }

     function getWethDeposit(address a) public view returns (uint256) {
         return wethDeposits[a];
     }

     function initWethConversion() public nonReentrant afterLP {
         require(!conversionDone, "CD");
         uint256 toSend = IERC20(weth).balanceOf(self) - wethDepositSum;
         TransferHelper.safeApprove(address(weth), address(twap), toSend);
         twap.supplyWETH(toSend);
         conversionDone = true;
     }

     function topUpWeth(uint256 amount) public afterLP returns (uint256 amountOut) {
         require(_msgSender() == creator, "PD");
         weth.safeTransferFrom(_msgSender(), self, amount);
         amountOut = swapWethForAltt(amount);
         notifier.notifyTopupWeth(creator, amount);
     }

     function swapWethForAltt(uint256 amountIn) internal returns (uint256 amountOut) {
        require(!lockSwap, "locked");
        lockSwap = true;
        TransferHelper.safeApprove(address(weth), address(swapRouter), amountIn);
        IV3SwapRouter.ExactInputSingleParams memory params =
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(asset()),
                fee: 100,
                recipient: self,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
        lockSwap = false;
    }

    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20) {
        require(from == address(0) || to == address(0) || from == self || to == self, "soulbound");
        super._update(from,to,amount);
    }

    function getRewards(address owner) public view returns (uint256) {
        uint256 assets =  _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        uint256 deposit = deposits[owner];
        uint256 rewards = 0;
        if (assets > deposit) rewards = assets - deposit;
        return rewards;
    }

    function unlockedShares(address owner) public view returns (uint256) {
        if (registry.getSubDetails(creator, owner) < block.timestamp) {
             return 0;
         }
         uint256 assets =  _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
         uint256 deposit = lastDeposit[owner].amount;
         uint256 rewards = 0;
         if (assets > deposit) rewards = assets - deposit;
         if (lastDeposit[owner].timestamp == 0) return 0;
         uint256 activeSub = Math.min(registry.getSubDetails(creator, owner), block.timestamp);
         uint256 daysSince = (activeSub - lastDeposit[owner].timestamp)/(1 days);
         if (daysSince >= 180) return balanceOf(owner);
         return _convertToShares((rewards/180)*daysSince, Math.Rounding.Ceil);
    }


    function unlockedRewards(address owner) public view returns (uint256) {
        if (registry.getSubDetails(creator, owner) < block.timestamp) {
            return 0;
        }
        uint256 assets =  _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        uint256 deposit = lastDeposit[owner].amount;
        uint256 rewards = 0;
        if (assets > lastDeposit[owner].amount) rewards = assets - lastDeposit[owner].amount;
        if (lastDeposit[owner].timestamp == 0) return 0;
        uint256 activeSub = Math.min(registry.getSubDetails(creator, owner), block.timestamp);
        uint256 daysSince = (activeSub - lastDeposit[owner].timestamp)/(1 days);
        if (daysSince >= 180) return rewards;
        return (rewards/180)*daysSince;
    }

    function penalizeUser(address owner, uint256 value) public {
        require(_msgSender() == address(registry), "PD");
        if (balanceOf(owner) == 0 || lastDeposit[owner].timestamp == 0) {
            return;
        }
        uint256 inactivityRatio = (value*1e18)/(block.timestamp - lastDeposit[owner].timestamp);
        boostLost[owner] = true;
        require(inactivityRatio > 0, "invalid penalty");
        uint256 penalty = 0;
        uint256 balanceInAssets = _convertToAssets(balanceOf(owner), Math.Rounding.Floor);
        // we only penalize rewards
        if (deposits[owner] < balanceInAssets) {
            penalty = Math.min(
                balanceInAssets - deposits[owner],
                (inactivityRatio*balanceInAssets)/1e18
            );
            uint256 penaltyInShares = _convertToShares(penalty, Math.Rounding.Ceil);
            penaltyInShares = Math.min(penaltyInShares, balanceOf(owner));
            _burn(owner, penaltyInShares);
            notifier.notifyPenalizedBoost(creator, owner, value);
        }
    }

    function getDeposit(address owner) public view returns (uint256) {
        return deposits[owner];
    }

    // https://docs.openzeppelin.com/contracts/5.x/erc4626
    function _decimalsOffset() internal view override(ERC4626) returns (uint8) {
        return 0;
    }

}
