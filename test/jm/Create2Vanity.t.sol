// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/Counter.sol";

/**
 * @title Create2VanityTest
 * @dev 验证 CREATE2 靓号部署: 搜索 salt -> 部署 -> 确认地址后缀
 *
 * 运行: forge test --match-path test/jm/Create2Vanity.t.sol -vvv --offline
 */
contract Create2VanityTest is Test {
    function testVanityDeploy() public {
        bytes32 initCodeHash = keccak256(type(Counter).creationCode);
        address deployer = address(this);
        // 目标片段 (十六进制), 例如 0x8888 表示 "8888"
        uint256 target = 0x8888;

        // 1. 搜索 salt
        bytes32 salt;
        address predicted;
        for (uint256 i = 0; i < 500000; i++) {
            predicted = _computeAddr(deployer, bytes32(i), initCodeHash);
            // 默认: 匹配后缀 (地址结尾), 取最后 16 bit
            bool isMatch = (uint160(predicted) & 0xFFFF) == target;

            // 前缀匹配示例: 把上面一行替换成下面这一行
            // bool isMatch = (uint160(predicted) >> 144) == target;

            if (isMatch) {
                salt = bytes32(i);
                break;
            }
        }
        require(predicted != address(0), unicode"未找到 salt");

        // 2. 部署
        Counter c = new Counter{salt: salt}();

        // 3. 验证
        assertEq(address(c), predicted);
        // 默认验证后缀
        assertEq(uint160(address(c)) & 0xFFFF, target);
        // 前缀验证示例:
        // assertEq(uint160(address(c)) >> 144, target);

        console.log(unicode"靓号地址:", address(c));
        console.log(unicode"Salt:", uint256(salt));
    }

    function _computeAddr(
        address d,
        bytes32 s,
        bytes32 h
    ) internal pure returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(hex"ff", d, s, h))))
            );
    }
}
