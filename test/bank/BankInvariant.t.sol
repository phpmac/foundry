// test/BankInvariant.t.sol
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../src/bank/Bank.sol";

/**
 * @title Bank合约不变量测试 (Invariant Test)
 * @notice 验证银行合约在极端随机操作下的资金安全性
 * @dev 使用 Foundry Invariant Fuzzer 进行有状态模糊测试
 *
 * 原理: Fuzzer 模拟大量随机交易(存/取款)进行压力测试
 * 目标: 验证合约真实余额始终等于所有用户账面余额之和
 *
 * 运行命令: forge test --match-test invariant
 */
contract BankInvariantTest is Test {
    Bank bank;
    address user1 = address(0x1111);
    address user2 = address(0x2222);

    function setUp() public {
        bank = new Bank();
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    // 不变量：合约余额应该始终等于所有用户余额之和
    function invariant_totalBalanceMatchesContractBalance() public view {
        uint256 totalUserBalance = bank.balances(user1) + bank.balances(user2);
        assertEq(address(bank).balance, totalUserBalance);
    }
}
