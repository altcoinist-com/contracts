// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./SubscribeRegistry.sol";
interface CSM {
     function execute(address target, uint256 value, bytes calldata data)
        external
        payable;
}

contract PaymentCollector is Ownable2Step {
    using SafeERC20 for IERC20;
    address public immutable altt;
    SubscribeRegistry public immutable registry;
    IERC20 public weth = IERC20(0x4200000000000000000000000000000000000006);
    bool pullLocked;
    address immutable self;
    uint256 public dateThreshold;
    mapping (address => uint256) lastRenewal;
    constructor (
        address _owner,
        address  _altt,
        address _registry
    ) Ownable(_owner) {
        require(_owner != address(0) && _altt != address(0) && _registry != address(0));
        altt = _altt;
        registry = SubscribeRegistry(_registry);
        pullLocked = false;
        dateThreshold = 1 days;
        self = address(this);
        weth.approve(address(registry), type(uint256).max);
    }

    /// @notice
    /// price updates by authors do not automatically
    /// affect subscribers.
    /// Subscribers who purchased a monthly sub at a fixed
    /// price will keep renewing at their initial price
    /// unless explicitly updating to the new price
    /// inside the registry
    function _pull(address subber, address author) internal {
        require(!pullLocked, "locked");
        require(lastRenewal[subber] < block.timestamp - 29 days);
        pullLocked = true;
        uint256 expiry = registry.getSubDetails(author, subber);
        if (block.timestamp >= expiry) {
            require(block.timestamp - expiry < dateThreshold, "late");
        } else {
            require(expiry - block.timestamp < dateThreshold, "early");
        }
        uint256 renewPrice = registry.getRenewPrice(author, subber);
        /*
         * bytes memory cd = abi.encodeWithSignature("transfer(address,uint256)", self, renewPrice);
         * CSM(subber).execute(address(weth), 0, cd);
         *require(weth.balanceOf(self) >= renewPrice, "CALLFAILED");
         */
        if (renewPrice > 0) {
            weth.safeTransferFrom(subber, self, renewPrice);
        }
        registry.subscribe(
            SubscribeRegistry.SubscribeParams(
            author,
            subber,
            SubscribeRegistry.packages.MONTHLY,
            1, // 1 month
            0, // no stake
            address(0) // no referral
        ));
        lastRenewal[subber] = block.timestamp;
        pullLocked = false;
    }

    function pull(address subber, address author) public onlyOwner {
        _pull(subber, author);
    }

    function pullBatch(address[] memory subbers, address[] memory authors) public onlyOwner {
        require(subbers.length == authors.length);
        for(uint i=0; i<subbers.length; i++) {
            _pull(subbers[i], authors[i]);
        }
    }

    function deprecate() public onlyOwner {
        pullLocked = true;
    }

    function setDateThreshold(uint256 _threshold) public onlyOwner {
        require(_threshold > 1 hours);
        dateThreshold = _threshold;
    }
}
