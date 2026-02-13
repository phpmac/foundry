// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/Counter.sol";

/**
 * @title DeployVanity
 * @dev 演示: 使用 CREATE2 将合约部署到靓号地址
 *
 * 用法:
 *   1. cast create2 --ends-with 1111 --init-code $(forge inspect Counter bytecode)
 *   2. 把 salt 写入 .env: VANITY_SALT=0x...
 *   3. forge script script/jm/DeployVanity.s.sol --broadcast
 */
contract DeployVanity is Script {
    function run() external {
        bytes32 salt = vm.envBytes32("VANITY_SALT");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        Counter c = new Counter{salt: salt}();
        console.log(unicode"部署地址:", address(c));

        vm.stopBroadcast();
    }
}
