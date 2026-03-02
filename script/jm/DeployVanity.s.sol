// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/jm/JMToken.sol";

/**
 * @title DeployVanity
 * @dev 使用 CREATE2 将 JMToken 部署到靓号地址
 *
 * 用法:
 *   1. 先编译: forge build
 *   2. 搜索 salt (以结尾8888为例):
 *      cast create2 --ends-with 8888 --init-code-hex $(cast abi-encode "f(bytes)" $(forge inspect src/jm/JMToken.sol:JMToken bytecode | cut -c2-)$(
 *        cast abi-encode "(address)" 0x10ED43C718714eb63d5aA57B78B54704E256024E | cut -c3-
 *      ) | cut -c3-)
 *
 *      或者更简单, 在 test 中用 vm.computeCreate2Address 计算
 *
 *   3. 把 salt 写入 .env: VANITY_SALT=0x...
 *   4. forge script script/jm/DeployVanity.s.sol --broadcast
 */
contract DeployVanity is Script {
    function run() external {
        bytes32 salt = vm.envBytes32("VANITY_SALT");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address pancakeRouter = vm.envAddress("PANCAKE_ROUTER");

        vm.startBroadcast(deployerKey);

        JMToken c = new JMToken{salt: salt}(pancakeRouter);
        console.log(unicode"部署地址:", address(c));

        vm.stopBroadcast();
    }
}
