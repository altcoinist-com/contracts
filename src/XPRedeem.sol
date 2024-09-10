// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "./ALTT.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";

contract XPRedeem is ReentrancyGuard {

    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;

    ALTT public immutable altt;
    address public immutable offchainSigner;
    uint256 public start;
    mapping (address => uint256) public redeemTimes;
    address immutable self;
    constructor (address _altt, address _signer) {
        require(_altt != address(0) && _signer != address(0));
        altt = ALTT(_altt);
        offchainSigner = _signer;
        start = 0;
        self = address(this);
    }

    event RedeemStarted(uint256 indexed timestamp);
    function startRedeem() public {
        require(msg.sender == offchainSigner && start == 0);
        start = block.timestamp;
        emit RedeemStarted(start);
    }

    event XPRedeemed(address indexed addr, uint256 amount, uint256 timestamp);
    function redeemXP(uint256 amount, uint256 deadline, bytes memory sig) public nonReentrant {
        require(deadline < block.timestamp && start > 0 && block.timestamp > start, "not yet");
        require(altt.balanceOf(self) >= amount, "BAL");
        require(redeemTimes[msg.sender] == 0, "already redeemed");
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        bytes32 hash = keccak256(abi.encodePacked(bytes("ALTT_SEP"), msg.sender, amount, chainId, deadline)).toEthSignedMessageHash();
        require(ECDSA.recover(hash, sig) == offchainSigner, "SIG");

        // penalty is 0.00001629x^3 + 5
        uint256 penaltyPct = 0;
        uint256 daysSince = (block.timestamp - start)/(1 days);
        if (daysSince < 180) { // to avoid precision errors
            penaltyPct = (1629*(daysSince**3)) + 5e8;
        } else {
            penaltyPct = 1e10;
        }
        uint256 penaltyAmount = (amount*penaltyPct)/1e10;
        IERC20(altt).safeTransfer(msg.sender, penaltyAmount);
        redeemTimes[msg.sender] = block.timestamp;
        emit XPRedeemed(msg.sender, penaltyAmount, block.timestamp);
    }

    function withdrawStuckALTT() public {
        require(msg.sender == offchainSigner, "PD");
        require(block.timestamp > start + 210 days, "not yet");
        IERC20(altt).safeTransfer(offchainSigner, altt.balanceOf(address(this)));
    }
}
