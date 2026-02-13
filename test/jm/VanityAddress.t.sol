// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "src/Counter.sol";

/**
 * @title VanityAddressTest
 * @dev 测试私钥部署 Counter 合约后地址后缀是否为靓号
 */
contract VanityAddressTest is Test {
    /**
     * @dev 使用环境变量 PRIVATE_KEY 部署 Counter 合约
     * 并验证合约地址后缀是否为目标靓号
     * 使用方法: source .env && forge test --match-test testDeployCounterVanityAddress -vvv --offline
     */
    function testDeployCounterVanityAddress() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log(unicode"部署者地址:", deployer);

        vm.startBroadcast(deployerPrivateKey);
        Counter counter = new Counter();
        vm.stopBroadcast();

        address contractAddr = address(counter);
        uint256 suffix = uint256(uint160(contractAddr)) % 0x10000;

        console.log(unicode"合约地址:", contractAddr);
        console.log(unicode"地址后缀(十进制):", suffix);
        console.log(unicode"地址后缀(十六进制):", vm.toString(bytes32(suffix)));

        // 验证后缀是否为靓号（4位重复数字）
        bool isVanity = _isVanitySuffix(suffix);
        assertTrue(isVanity, unicode"合约地址后缀应该是靓号(4位重复数字如0x1111, 0x2222等)");
    }

    /**
     * @dev 检查后缀是否为靓号(4位重复数字)
     * 支持: 0x0000, 0x1111, 0x2222, ..., 0xFFFF
     */
    function _isVanitySuffix(uint256 suffix) internal pure returns (bool) {
        require(suffix <= 0xFFFF, unicode"后缀必须是4位十六进制");

        // 提取4个十六进制位
        uint256 d1 = (suffix >> 12) & 0xF;  // 最高位
        uint256 d2 = (suffix >> 8) & 0xF;
        uint256 d3 = (suffix >> 4) & 0xF;
        uint256 d4 = suffix & 0xF;          // 最低位

        // 检查是否4位都相同
        return d1 == d2 && d2 == d3 && d3 == d4;
    }
}
