// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "swap-router-contracts/interfaces/IV3SwapRouter.sol";
import "@uniswap/v3-periphery/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "./StakingFactory.sol";
import "./StakingVault.sol";
import "./ALTT.sol";
import "./CreatorTokenFactory.sol";
import "./Notifier.sol";

contract SubscribeRegistry is ERC2771Context, Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    enum packages {
      MONTHLY,
      LIFETIME
    }
    address immutable self;
    ALTT public immutable altt;
    mapping (address => mapping (address => uint256)) subDir;
    mapping (address => mapping (packages => uint256)) public subPrices;
    mapping (address => mapping (address => uint256)) renewPrice;
    bool distributeLocked;

    mapping (address => bool) initialized;

    IERC20 immutable weth;
    IV3SwapRouter immutable swapRouter;
    StakingFactory stakingFactory;
    CreatorTokenFactory creatorTokenFactory;
    VaultNotifier vaultNotifier;
    TWAP twap;
    address immutable ecosystemAddress;
    uint256 public wethVaults;
    uint256 renewThreshold;

    constructor(address _altt, address _eco)
        ERC2771Context(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789)
        Ownable(_msgSender()) {
        require(_altt != address(0) && _eco != address(0));
        altt = ALTT(_altt);
        weth = IERC20(0x4200000000000000000000000000000000000006);
        swapRouter = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481); // mainnet
        //swapRouter = IV3SwapRouter(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4); // sepolia
        ecosystemAddress = _eco;
        self = address(this);
        distributeLocked = false;
        renewThreshold = 12 hours;
    }

    function getSubDetails(address creator, address follower)
        public
        view
        returns (uint256) {
            return subDir[creator][follower];
    }

    struct SubscribeParams {
        address creator;
        address subber;
        packages package;
        uint256 qty;
        uint256 stakeAmount;
        address ref;
    }

    event Subscribed(address subber, address indexed creator, packages package, uint256 expiry, uint256 price, address ref);
    function subscribe(SubscribeParams calldata params) external nonReentrant {
        require(!distributeLocked, "locked");
        require(params.qty > 0, "QTY");
        require(stakingFactory.vaults(params.creator) != address(0), "UV");
        require(params.ref == address(0) || params.ref != params.subber, "SELFREF");
        require(params.subber != params.creator, "SELFSUB");
        uint256 prevExpiry = getSubDetails(params.creator, params.subber);
        require(prevExpiry != type(uint256).max, "ALS");
        uint256 expiry = prevExpiry;
        bool shouldNotifyPool = expiry != 0 && expiry < block.timestamp;
        uint256 basePrice = subPrices[params.creator][params.package];

        if (
            renewPrice[params.creator][params.subber] > 0 &&
            prevExpiry >= block.timestamp
            && params.package == packages.MONTHLY
        ) {
            basePrice = renewPrice[params.creator][params.subber];
        }

        address vault = stakingFactory.vaults(params.creator);
        if (expiry < block.timestamp) {
            expiry = block.timestamp;
        }
        if (params.package == packages.MONTHLY) {
            basePrice = basePrice * params.qty;
            expiry += params.qty*(30 days);
        } else if (params.package == packages.LIFETIME) {
            require(params.qty == 1);
            expiry = type(uint256).max;
        } else {
            revert("IP");
        }

        if (basePrice != 0) {
            require(weth.balanceOf(_msgSender()) >= basePrice, "IB");
            _distributeFunds(params.creator, _msgSender(), basePrice, params.ref);
            distributeLocked = false;
        }

        if (!canStake(params.creator, params.subber)) {
            _mintStakingNFT(params.creator, params.subber);
        }
        if (shouldNotifyPool) {
            StakingVault(vault).penalizeUser(params.subber, block.timestamp - prevExpiry);
        }

        if (params.stakeAmount > 0) {
            if(altt.isAfterLP()) {
                TransferHelper.safeTransferFrom(address(altt), _msgSender(), self, params.stakeAmount);
                TransferHelper.safeApprove(address(altt), vault, params.stakeAmount);
                StakingVault(vault).deposit(params.stakeAmount, params.subber);
            } else {
                require(weth.balanceOf(_msgSender()) >= params.stakeAmount, "WETHBAL");
                weth.safeTransferFrom(_msgSender(), self, params.stakeAmount);
                uint256 sent = StakingVault(vault).depositWeth(params.subber, params.stakeAmount);
                require(sent == params.stakeAmount, "failed to stake all tokens");
            }
        }

        subDir[params.creator][params.subber] = expiry;

        if (params.package == packages.MONTHLY
            &&  prevExpiry < block.timestamp - renewThreshold) {
            renewPrice[params.creator][params.subber] = basePrice;
        }

        emit Subscribed(params.subber, params.creator, params.package, expiry, basePrice, params.ref);
    }

    function _distributeFunds(address creator, address sender, uint256 basePrice, address ref) internal {
        require(!distributeLocked);
        distributeLocked = true;
        uint256 toCreator = 0;
        uint256 toPool = 0;
        uint256 toEcosystem = 0;
        uint256 toReferer = 0;
        address vault = stakingFactory.vaults(creator);
        if(ref != address(0)) {
            toCreator = (basePrice * 7200) / 10000; // 72%
            toPool = (basePrice * 1200) / 10000; // 12%
            toReferer = (basePrice*800)/10000; // 8%
            toEcosystem = basePrice - toCreator - toPool - toReferer; // 8% - ref%
            weth.safeTransferFrom(sender, ref, toReferer);
        } else {
            toCreator = (basePrice * 8000) / 10000; // 80%
            toPool = (basePrice * 1200) / 10000; // 12%
            toEcosystem = basePrice - toCreator - toPool; // 8% ecosystem
        }
        weth.safeTransferFrom(sender, creator, toCreator);
        weth.safeTransferFrom(sender, self, toPool);
        if (altt.isAfterLP()) { // rewards are only sent after TGE
            uint256 alttReceived = swapWethForAltt(toPool);
            TransferHelper.safeApprove(address(altt), vault, alttReceived);
            TransferHelper.safeTransfer(address(altt), vault, alttReceived);
        } else {
            uint256 sent = StakingVault(vault).depositWeth(vault, toPool);
            require(sent == toPool);
        }
        weth.safeTransferFrom(sender, ecosystemAddress, toEcosystem);
    }

    event StakingNFTMinted(address creator, address staker);
    function _mintStakingNFT(address creator, address staker) internal {
        creatorTokenFactory.mint(staker, uint256(uint160(creator)), 1, bytes(""));
        emit StakingNFTMinted(creator, staker);
    }

    function setSubPrice(uint256 monthly, uint256 lifetime, string memory uname) public nonReentrant {
        require(address(stakingFactory) != address(0) && address(creatorTokenFactory) != address(0));
        require((monthly < lifetime && monthly > 1e6) || (monthly == 0 && lifetime == 0), "IP");
        if (!initialized[_msgSender()]) {
            // the vault is created with a CLONE so address(this)
            // refers to the factory at time of creation.
            // To mitigate delegate vulnerabilities, we supply
            // its own address as a parameter.
            StakingVault newVault = StakingVault(stakingFactory.createPool(_msgSender()));
            weth.approve(address(newVault), type(uint256).max);
            newVault.init(
                address(newVault),
                _msgSender(),
                uname,
                address(stakingFactory),
                address(creatorTokenFactory),
                address(vaultNotifier),
                address(twap)
            );
            initialized[_msgSender()] = true;
            if (!altt.isAfterLP()) {
                wethVaults += 1;
            }
        }
        subPrices[_msgSender()][packages.MONTHLY] = monthly;
        subPrices[_msgSender()][packages.LIFETIME] = lifetime;
    }


    function setFactories(
        address _stakingFactory,
        address _creatorTokenFactory,
        address _notifier,
        address _twap
    ) public onlyOwner {
        require(_stakingFactory != address(0));
        require(_creatorTokenFactory != address(0));
        require(_twap != address(0));
        require(_notifier != address(0));
        stakingFactory = StakingFactory(_stakingFactory);
        creatorTokenFactory = CreatorTokenFactory(_creatorTokenFactory);
        vaultNotifier = VaultNotifier(_notifier);
        twap = TWAP(_twap);
        // renounceOwnership();
    }

    
    function getRenewPrice(address creator, address subber) public view returns (uint256) {
        return renewPrice[creator][subber];
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address) {
        return ERC2771Context._msgSender();
    }
    
    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function getSubPrice(address creator, packages package) public view returns (uint256) {
        return subPrices[creator][package];
    }

    /*
    event Unsubscribed(address indexed creator, address subber);
    function unsubscribe(address creator, address subber) public {
        uint256 expiry = getSubDetails(creator, subber);
        require(_msgSender() == subber, "PD");
        require(expiry > 0 && expiry < type(uint256).max, "ALS");
        subDir[creator][subber] = block.timestamp - 1 days - 1 minutes;
        emit Unsubscribed(creator, subber);
    }
    */
    
    function swapWethForAltt(uint256 amountIn) internal returns (uint256 amountOut) {
        require(weth.balanceOf(self) >= amountIn, "BAL");
        TransferHelper.safeApprove(address(weth), address(swapRouter), amountIn);
        IV3SwapRouter.ExactInputSingleParams memory params =
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(altt),
                fee: 100,
                recipient: self,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0 // FIXME MEV ISSUE
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function canStake(address creator, address account) public view returns (bool) {
        return creatorTokenFactory.balanceOf(account, uint256(uint160(creator))) > 0;
    }

    function setRenewThreshold(uint256 _t) public onlyOwner() {
        require(_t > 1 hours);
        renewThreshold = _t;
    }

}
