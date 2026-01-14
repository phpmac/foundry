// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @title 溢出原理详解测试
/// @notice 一步步演示溢出是如何发生的
contract OverflowExplainTest is Test {
    /// @notice 演示uint256的最大值和溢出
    function test_Step1_Uint256Max() public pure {
        // uint256最大值 = 2^256 - 1
        uint256 maxValue = type(uint256).max;

        console.log(unicode"=== 第1步: 理解uint256范围 ===");
        console.log(unicode"uint256最大值:");
        console.log(maxValue);
        // 约等于 1.15 * 10^77

        // 当数值超过最大值时,会"回绕"到0重新开始
        // 类似汽车里程表: 999999 + 1 = 000000
    }

    /// @notice 演示2^128的平方如何溢出
    function test_Step2_OverflowMath() public pure {
        console.log(unicode"=== 第2步: 2^128的平方 ===");

        uint256 amount = 2 ** 128;
        console.log(unicode"amount = 2^128 =");
        console.log(amount);
        // = 340282366920938463463374607431768211456

        // 计算 amount * amount = (2^128)^2 = 2^256
        // 但是! 2^256 超过了 uint256 最大值 (2^256 - 1)
        // 所以发生溢出: 2^256 mod 2^256 = 0

        uint256 squared;
        unchecked {
            squared = amount * amount; // 使用unchecked模拟旧版Solidity
        }

        console.log(unicode"amount * amount (溢出后) =");
        console.log(squared);
        // = 0 !!!

        assertEq(squared, 0, unicode"2^256 溢出为 0");
    }

    /// @notice 演示完整的成本计算
    function test_Step3_CostCalculation() public pure {
        console.log(unicode"=== 第3步: 成本计算公式 ===");
        console.log(unicode"公式: cost = (100 * amount^2 * reserve) / 1e36");
        console.log("");

        uint256 reserve = 1000 ether; // 1000 * 10^18

        // ===== 正常用户 =====
        console.log(unicode"--- 正常用户: amount = 1000 ---");
        uint256 normalAmount = 1000;

        // 分步计算
        uint256 step1 = normalAmount * normalAmount; // 1000 * 1000 = 1,000,000
        console.log(unicode"step1: amount * amount =");
        console.log(step1);

        uint256 step2 = 100 * step1; // 100 * 1,000,000 = 100,000,000
        console.log(unicode"step2: 100 * step1 =");
        console.log(step2);

        uint256 step3 = step2 * reserve; // 100,000,000 * 10^21 = 10^29
        console.log(unicode"step3: step2 * reserve =");
        console.log(step3);

        uint256 normalCost = step3 / 1e36; // 10^29 / 10^36 = 10^-7 ≈ 0
        console.log(unicode"最终成本: step3 / 1e36 =");
        console.log(normalCost);

        console.log("");

        // ===== 攻击者 =====
        console.log(unicode"--- 攻击者: amount = 2^128 ---");
        uint256 attackAmount = 2 ** 128;

        uint256 attackStep1;
        uint256 attackStep2;
        uint256 attackStep3;

        unchecked {
            attackStep1 = attackAmount * attackAmount; // 2^256 mod 2^256 = 0 !!!
            console.log(unicode"step1: amount * amount = (溢出!)");
            console.log(attackStep1);

            attackStep2 = 100 * attackStep1; // 100 * 0 = 0
            console.log(unicode"step2: 100 * step1 =");
            console.log(attackStep2);

            attackStep3 = attackStep2 * reserve; // 0 * reserve = 0
            console.log(unicode"step3: step2 * reserve =");
            console.log(attackStep3);
        }

        uint256 attackCost = attackStep3 / 1e36; // 0 / 1e36 = 0
        console.log(unicode"最终成本: step3 / 1e36 =");
        console.log(attackCost);

        console.log("");
        console.log(unicode"=== 结论 ===");
        console.log(unicode"正常用户铸造 1000 代币, 成本:");
        console.log(normalCost);
        console.log(unicode"攻击者铸造 2^128 代币, 成本:");
        console.log(attackCost);
        console.log(unicode"攻击者获得代币数量:");
        console.log(attackAmount);

        // 攻击者用0成本获得了天文数字的代币!
        assertEq(attackCost, 0, unicode"攻击者成本为0");
    }

    /// @notice 用更简单的数字演示溢出原理
    function test_Step4_SimpleOverflowDemo() public pure {
        console.log(unicode"=== 第4步: 简化演示 (假设最大值是255) ===");
        console.log(unicode"想象uint8: 最大值255, 256会溢出为0");
        console.log("");

        // 用uint8演示 (最大值255)
        uint8 a = 200;
        uint8 b = 100;

        uint8 result;
        unchecked {
            result = a + b; // 200 + 100 = 300, 但300 > 255, 所以 300 - 256 = 44
        }

        console.log(unicode"uint8: 200 + 100 = (溢出后)");
        console.log(result); // 44

        console.log("");
        console.log(unicode"同理, uint256中:");
        console.log(unicode"2^256 超过最大值, 溢出后 = 0");
    }
}
