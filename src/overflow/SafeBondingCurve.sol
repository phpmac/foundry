// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; // ! 默认溢出检查

/// @title 安全版本: Bonding Curve
/// @notice 使用Solidity 0.8+默认溢出保护
contract SafeBondingCurve {
    uint256 public totalSupply;
    uint256 public reserve;

    mapping(address => uint256) public balanceOf;

    constructor() {
        reserve = 1000 ether;
        totalSupply = 1000000e18;
    }

    /// @notice 安全计算铸造成本
    /// @dev Solidity 0.8+会在溢出时自动revert
    function calculateCost(uint256 amount) public view returns (uint256) {
        // 0.8+: 溢出会自动revert,攻击者无法利用
        uint256 term1 = 100 * amount * amount * reserve;
        uint256 term2 = 200 * totalSupply * amount * reserve;
        uint256 numerator = term1 + term2;

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

    receive() external payable {
        reserve += msg.value;
    }
}
