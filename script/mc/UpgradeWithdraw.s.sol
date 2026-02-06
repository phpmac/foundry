// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Withdraw} from "../../src/mc/Withdraw.sol";

/**
 * @title UpgradeWithdrawScript
 * @dev Withdraw 合约 UUPS 升级脚本
 *
 * 运行命令:
 * forge script script/mc/UpgradeWithdraw.s.sol --broadcast
 */
contract UpgradeWithdrawScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address proxyAddress = vm.envAddress("WITHDRAW_PROXY_ADDRESS");

        require(proxyAddress != address(0), unicode"WITHDRAW_PROXY_ADDRESS 未设置");

        Withdraw proxy = Withdraw(proxyAddress);

        console.log(unicode"=== 升级配置 ===");
        console.log(unicode"执行者:", deployer);
        console.log(unicode"代理地址:", proxyAddress);
        console.log(unicode"================\n");

        vm.startBroadcast(deployerPrivateKey);

        // 部署新实现合约
        console.log(unicode"部署新实现合约...");
        Withdraw newImpl = new Withdraw();
        console.log(unicode"新实现地址:", address(newImpl));

        // 通过 UUPS 升级
        console.log(unicode"执行升级...");
        proxy.upgradeToAndCall(address(newImpl), "");

        // 验证
        console.log(unicode"执行健康检查...");
        proxy.healthcheck();
        console.log(unicode"健康检查通过");

        vm.stopBroadcast();

        console.log(unicode"\n=== 升级摘要 ===");
        console.log(unicode"代理地址 (不变):", proxyAddress);
        console.log(unicode"新实现合约:", address(newImpl));
    }
}
