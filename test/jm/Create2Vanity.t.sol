// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/jm/JMToken.sol";

/**
 * @title Create2VanityTest
 * @dev 验证 CREATE2 地址计算和部署一致性
 *
 * 查找 salt 请使用: forge script script/jm/FindVanitySalt.s.sol --offline
 */
contract Create2VanityTest is Test {
    function testCreate2AddressConsistency() public {
        address pancakeRouter = vm.envAddress("PANCAKE_ROUTER");
        bytes32 salt = vm.envBytes32("VANITY_SALT"); // 从 .env 读取 FindVanitySalt 找到的 salt
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // initCode = creationCode + encoded constructor args
        bytes memory initCode = abi.encodePacked(
            type(JMToken).creationCode,
            abi.encode(pancakeRouter)
        );
        bytes32 initCodeHash = keccak256(initCode);

        // 计算预期地址
        address predicted = _computeAddr(deployer, salt, initCodeHash);

        // 使用 vm.prank 模拟从 deployer 地址部署
        vm.prank(deployer);
        JMToken c = new JMToken{salt: salt}(pancakeRouter);

        // 验证地址一致
        assertEq(address(c), predicted, unicode"CREATE2 地址不一致");

        console.log(unicode"Salt:", uint256(salt));
        console.log(unicode"预测地址:", predicted);
        console.log(unicode"实际地址:", address(c));
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
