// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @title 溢出攻击测试
/// @notice 演示Truebit类型漏洞的攻击和防御
contract OverflowAttackTest is Test {
    /// @notice 演示溢出回绕原理
    function test_OverflowWrapAround() public pure {
        uint256 reserve = 1000 ether;

        // 正常计算: 小额amount
        uint256 smallAmount = 1000e18;
        uint256 normalResult;
        unchecked {
            normalResult = 100 * smallAmount * smallAmount * reserve;
        }

        // 溢出攻击: amount = 2^128
        // 计算: 100 * (2^128)^2 * reserve
        // = 100 * 2^256 * reserve
        // = 0 (因为2^256 mod 2^256 = 0)
        uint256 attackAmount = 2 ** 128;
        uint256 overflowedResult;
        unchecked {
            overflowedResult = 100 * attackAmount * attackAmount * reserve;
        }

        console.log(unicode"正常结果 (1000e18 代币):", normalResult);
        console.log(unicode"溢出结果 (2^128 代币):", overflowedResult);
        console.log(unicode"攻击数量:", attackAmount);

        // 关键断言: 溢出后term1为0!
        assertEq(overflowedResult, 0, unicode"term1 溢出为 0!");

        // 攻击者获得的代币数量 vs 支付成本
        console.log(unicode"攻击者获得代币:", attackAmount);
        console.log(unicode"攻击者支付 (仅term1):", overflowedResult);
    }

    /// @notice 演示Solidity 0.8+的保护
    function test_SafeMathReverts() public {
        uint256 amount = 2 ** 128;
        uint256 reserve = 1000 ether;

        // 0.8+默认会revert
        vm.expectRevert();
        this.unsafeCalculation(amount, reserve);
    }

    /// @notice 外部函数用于测试revert
    function unsafeCalculation(
        uint256 amount,
        uint256 reserve
    ) external pure returns (uint256) {
        // 没有unchecked,0.8+会自动检查溢出
        return 100 * amount * amount * reserve;
    }

    /// @notice 模拟完整攻击流程
    function test_AttackScenario() public {
        // 初始状态
        uint256 reserve = 1000 ether;
        uint256 totalSupply = 1000000e18;

        // 攻击者尝试不同的amount寻找最佳溢出点
        uint256 bestAmount;
        uint256 lowestCost = type(uint256).max;

        // 搜索溢出点(简化演示)
        for (uint256 i = 100; i < 150; i++) {
            uint256 testAmount = 2 ** i;

            unchecked {
                uint256 term1 = 100 * testAmount * testAmount * reserve;
                uint256 term2 = 200 * totalSupply * testAmount * reserve;
                uint256 cost = (term1 + term2) / 1e36;

                if (cost < lowestCost && cost < 1 ether) {
                    lowestCost = cost;
                    bestAmount = testAmount;
                }
            }
        }

        console.log(unicode"最佳攻击数量 (2^n):", bestAmount);
        console.log(unicode"海量代币的成本:", lowestCost);
        console.log(unicode"获得代币:", bestAmount);

        // 攻击成功条件: 成本极低但获得大量代币
        if (lowestCost < 1 ether && bestAmount > 1e30) {
            console.log(unicode"攻击成功: 近零成本获得海量代币!");
        }
    }

    /// @notice 测试边界值
    function test_BoundaryValues() public pure {
        // 测试接近溢出边界的值
        uint256[] memory testValues = new uint256[](5);
        testValues[0] = 2 ** 64;
        testValues[1] = 2 ** 85; // 常见溢出点
        testValues[2] = 2 ** 100;
        testValues[3] = 2 ** 128;
        testValues[4] = 2 ** 200;

        uint256 reserve = 1000 ether;

        for (uint256 i = 0; i < testValues.length; i++) {
            unchecked {
                uint256 result = 100 * testValues[i] * testValues[i] * reserve;
                console.log(unicode"2^n 输入, 结果:", testValues[i], result);
            }
        }
    }
}
