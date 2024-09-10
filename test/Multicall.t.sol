// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "./TestEnv.t.sol";
import {PaymentCollector} from "../src/PaymentCollector.sol"; 
import "../src/StakingVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICSMFactory {
     function createAccount(bytes[] calldata owners, uint256 nonce)
        external
         payable
        virtual
        returns (address);
}

interface CSM {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }
     function executeBatch(Call[] memory calls)
        external
        payable;
    error Initialized();
    error SelectorNotAllowed(bytes4 selector);
    error InvalidNonceKey(uint256 key);
}
contract MulticallTest is Test {
    ICSMFactory factory = ICSMFactory(0x0BA5ED0c6AA8c49038F819E587E2633c4A9F428a);
    PaymentCollector public paymentCollector;
    TestEnv env;
    StakingVault vault;
    CSM aliceCSM;
    CSM bobCSM;
    IERC20 weth;


    function setUp() public {
        env = new TestEnv();
        paymentCollector = new PaymentCollector(
            env.accounts(0),
            address(env.altt()),
            address(env.registry())
        );
        address alice = env.accounts(1);
        address bob = env.accounts(2);
        vm.startPrank(alice);
        // create CSM wallet for alice & bob
        bytes[] memory owners = new bytes[](2);
        owners[0] = abi.encode(alice);
        owners[1] = abi.encode(address(paymentCollector));
        aliceCSM = CSM(factory.createAccount(owners, 0));

        assertTrue(address(aliceCSM) != address(0));
        weth = env.weth();
    }

    function test_canMulticallFromOwner() public {
        vm.startPrank(env.accounts(1));
        uint256 amount = 1e18;
        deal(address(aliceCSM), amount);
        CSM.Call[] memory calls = new CSM.Call[](3);
        calls[0] = CSM.Call(address(weth), amount, abi.encodeWithSignature("deposit()"));
        calls[1] = CSM.Call(address(weth), 0, abi.encodeWithSignature("approve(address,uint256)", address(env.registry()), amount));
        calls[2] = CSM.Call(address(env.registry()), 0, abi.encodeWithSignature("setSubPrice(uint256,uint256,string)", 1e18, 5e18, "JSmith"));

        aliceCSM.executeBatch(calls);

        assertEq(weth.balanceOf(address(aliceCSM)), amount);
        address vaultAddr = env.stakingFactory().vaults(address(aliceCSM));
        assertTrue(vaultAddr != address(0), "uninitialized vault");
    }
}
