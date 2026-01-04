// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/**
 * 简单的银行合约示例
 *
 * 功能: 支持ETH存入和提取
 * 注意: 代码中故意包含重入漏洞用于测试演示
 */
contract Bank {
    mapping(address => uint256) public balances;

    /**
     * @notice 存款
     * @dev 存款不会存在重入漏洞
     */
    function deposit() public payable {
        balances[msg.sender] += msg.value;
    }

    /**
     * @notice 提取资金
     * @dev
     * 遵循 Checks-Effects-Interactions 模式
     * 这个是故意存在漏洞的版本
     * 1. Checks: 检查条件 (已做)
     * 2. Effects: 先更新状态
     * 3. Interactions: 最后进行外部交互
     */
    function withdraw(uint256 amount) public {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // ! 漏洞: 经典重入漏洞（reentrancy）
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Transfer failed");

        // 演示用: 使用 unchecked 绕过 Solidity 0.8+ 的溢出检查
        // 在真实旧版代码中，这会导致下溢，变成巨大的数字
        unchecked {
            balances[msg.sender] -= amount;
        }
    }

    /**
     * @notice 安全的提款函数
     * @dev 遵循 Checks-Effects-Interactions 模式防止重入攻击
     * @param amount 提款金额
     */
    function withdrawSafe(uint256 amount) public {
        // 1. Checks
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // 2. Effects
        balances[msg.sender] -= amount;

        // 3. Interactions
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Transfer failed");
    }
}
