// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MC} from "../../src/mc/MC.sol";

/**
 * @title DeliverToClientScript
 * @dev 交接脚本: 将代币转给客户并设置白名单
 */
contract DeliverToClientScript is Script {
    // MC 合约地址
    address public constant MC_ADDRESS =
        0xcD0c229a02a9fBCbb6a19347a48d004c46d7e4d1;

    // 客户地址
    address public constant CLIENT_ADDRESS =
        0x348d62c4134be9B03E324B1d1A981627EAF47695;

    // Owner 私钥地址
    address public constant OWNER = 0x20F7acfc15a4EB3142F6d1DdFb219a660541484e;

    function run() external {
        // Fork BSC mainnet
        uint256 forkId = vm.createFork("bsc_mainnet");
        vm.selectFork(forkId);

        // 获取 owner 私钥
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(vm.addr(ownerPrivateKey) == OWNER, "Invalid private key");

        // 加载 MC 合约
        MC mc = MC(MC_ADDRESS);

        console.log(unicode"=== 开始交接流程 ===");

        // 1. 设置白名单 (如果客户地址不是白名单)
        bool isWhitelisted = mc.isWhitelisted(CLIENT_ADDRESS);
        if (!isWhitelisted) {
            console.log(unicode"设置白名单...");
            vm.startBroadcast(ownerPrivateKey);
            mc.setWhitelist(CLIENT_ADDRESS, true);
            vm.stopBroadcast();
            console.log(unicode"✓ 白名单设置完成");
            console.log(unicode"客户地址:", CLIENT_ADDRESS);
        } else {
            console.log(unicode"客户地址已在白名单中, 跳过设置");
        }

        // 2. 转账 owner 余额给客户 (如果启用且余额大于0)
        uint256 ownerBalance = mc.balanceOf(OWNER);
        console.log(unicode"Owner MC余额:", ownerBalance / 1e18);

        if (ownerBalance > 0) {
            console.log(unicode"转账 owner 余额给客户...");
            vm.startBroadcast(ownerPrivateKey);
            mc.transfer(CLIENT_ADDRESS, ownerBalance);
            vm.stopBroadcast();

            // 验证结果
            uint256 balanceAfter = mc.balanceOf(OWNER);
            uint256 clientBalance = mc.balanceOf(CLIENT_ADDRESS);
            console.log(unicode"✓ 转账完成");
            console.log(unicode"Owner 余额后:", balanceAfter / 1e18);
            console.log(unicode"客户余额:", clientBalance / 1e18);
        } else {
            console.log(unicode"Owner 余额为0, 跳过转账");
        }

        console.log(unicode"=== 交接流程完成 ===");
    }
}
