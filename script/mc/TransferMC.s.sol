// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MC} from "../../src/mc/MC.sol";

contract TransferMCScript is Script {
    // MC 合约地址
    address public constant MC_ADDRESS = 0x01e2FddC7A7499D9d888ccac239Ce9Fb13a7133D;

    // 接收地址
    address public constant RECIPIENT = 0x348d62c4134be9B03E324B1d1A981627EAF47695;

    // Owner 私钥地址
    address public constant OWNER = 0x20F7acfc15a4EB3142F6d1DdFb219a660541484e;

    function run() external {
        // Fork BSC mainnet (使用 foundry.toml 中配置的 rpc_endpoints)
        uint256 forkId = vm.createFork("bsc_mainnet");
        vm.selectFork(forkId);

        // 获取 owner 私钥
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        require(vm.addr(ownerPrivateKey) == OWNER, "Invalid private key");

        // 加载 MC 合约
        MC mc = MC(MC_ADDRESS);

        // 查询 owner 余额
        uint256 balanceBefore = mc.balanceOf(OWNER);
        console.log("Owner MC balance:", balanceBefore / 1e18);
        require(balanceBefore > 0, "Owner MC balance is 0");

        // 转账全部余额
        vm.startBroadcast(ownerPrivateKey);
        mc.transfer(RECIPIENT, balanceBefore);
        vm.stopBroadcast();

        // 验证结果
        uint256 balanceAfter = mc.balanceOf(OWNER);
        uint256 recipientBalance = mc.balanceOf(RECIPIENT);

        console.log("Transfer completed");
        console.log("Owner balance after:", balanceAfter / 1e18);
        console.log("Recipient balance:", recipientBalance / 1e18);
        console.log("Recipient:", RECIPIENT);
    }
}
