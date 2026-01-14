// SPDX-License-Identifier: MIT
pragma solidity 0.7.6; // ! 旧版本,无默认溢出检查

/// @title 漏洞示例: Bonding Curve溢出攻击
/// @notice 模拟Truebit漏洞 - 仅用于教育目的
contract VulnerableBondingCurve {
    uint256 public totalSupply;
    uint256 public reserve;

    mapping(address => uint256) public balanceOf;

    constructor() {
        reserve = 1000 ether;
        totalSupply = 1000000e18;
    }

    /// @notice 漏洞函数: 计算铸造成本
    /// @dev 公式: (100 * amount^2 * reserve + 200 * totalSupply * amount * reserve) / 1e36
    /// @param amount 要铸造的代币数量
    function calculateCost(uint256 amount) public view returns (uint256) {
        // 危险: 这些乘法在amount极大时会溢出回绕
        uint256 term1 = 100 * amount * amount * reserve;
        uint256 term2 = 200 * totalSupply * amount * reserve;
        uint256 numerator = term1 + term2;

        // SafeDiv无法修复已溢出的numerator
        uint256 cost = numerator / 1e36;
        return cost;
    }

    /// @notice 铸造代币
    function mint(uint256 amount) external payable {
        uint256 cost = calculateCost(amount);
        require(msg.value >= cost, "insufficient payment");

        balanceOf[msg.sender] += amount;
        totalSupply += amount;
        reserve += msg.value;
    }

    /// @notice 提取储备金(简化)
    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;

        uint256 payout = (amount * reserve) / totalSupply;
        totalSupply -= amount;
        reserve -= payout;

        payable(msg.sender).transfer(payout);
    }

    receive() external payable {
        reserve += msg.value;
    }
}
