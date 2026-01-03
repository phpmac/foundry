// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * 运行命令:
 *
 * 测试签名恢复:
 * forge test --match-test test_RecoverSigner -vvv
 *
 * 测试提现:
 * forge test --match-test test_Withdrawal -vvv
 *
 * 运行所有测试:
 * forge test -vvv
 *
 * 使用其他Optimism RPC节点:
 * forge test --match-test test_RecoverSigner -vvv --fork-url https://mainnet.optimism.io
 * forge test --match-test test_Withdrawal -vvv --fork-url https://mainnet.optimism.io
 */

import {Test, console} from "forge-std/Test.sol";
import {Withdraw} from "../src/Withdraw.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract WithdrawTest is Test {
    using ECDSA for bytes32;

    // Optimism主网RPC URL
    string constant OP_RPC_URL = "https://mainnet.optimism.io";

    // 真实数据
    address public user = 0xb912B5CfEdD5e7A2e253B3073af7e61E92271184;
    address public tokenAddress = 0x37e7B62686538A501828A6B931216d51F9a0D5b4;
    address public withdrawContract =
        0x0CA8CE179aC368aa7d3C657421799dC872FEf7bc;

    uint256 public amount = 52988560000000000000; // 52.98856 * 10^18
    uint256 public nonce = 101;
    uint256 public deadline = 1766762177;
    bytes public signature =
        hex"7fe112220fabae914e2041671cb3812f2ce9953be939755ffb0210a63e45eda57bc333c2a50b5f733d4990da249d42c8846e61673d1a6471370aae9b910de21b1c";

    Withdraw public withdraw;

    function setUp() public {
        // Fork Optimism主网 (Optimism Chain ID = 10)
        vm.createSelectFork(OP_RPC_URL);

        console.log("Forked Optimism, Chain ID:", block.chainid);
        console.log("Expected Optimism Chain ID: 10");

        // 检查合约是否存在
        address contractAddr = withdrawContract;
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(contractAddr)
        }

        console.log("Contract address:", uint256(uint160(contractAddr)));
        console.log("Contract code size:", codeSize);

        if (codeSize == 0) {
            console.log(
                "ERROR: Contract does not exist at this address on Optimism"
            );
            console.log("Please verify the contract address is correct");
            revert("Contract does not exist at this address");
        }

        // 使用真实合约地址
        withdraw = Withdraw(withdrawContract);
    }

    function test_RecoverSigner() public view {
        // 从签名恢复签名者地址
        (bytes32 signMessage, ) = withdraw.getSignNonceMessage(
            nonce,
            user,
            amount,
            tokenAddress,
            deadline
        );

        bytes memory sig = signature;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        address recoveredSigner = signMessage.recover(v, r, s);

        console.log("Recovered signer:", recoveredSigner);
        console.log("Contract signer:", withdraw.withdrawalSignAddress());
        console.log("Chain ID:", block.chainid);
        console.log("Current time:", block.timestamp);
        console.log("Deadline:", deadline);

        // 验证恢复的签名者是否等于预期签名者
        assertEq(
            recoveredSigner,
            withdraw.withdrawalSignAddress(),
            "Recovered signer does not match contract signer"
        );
    }

    function test_Withdrawal() public {
        // 使用用户地址调用
        vm.prank(user);

        withdraw.withdrawal(amount, tokenAddress, nonce, deadline, signature);
    }
}
