// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MC} from "../../src/mc/MC.sol";
import {TaxDistributor} from "../../src/mc/TaxDistributor.sol";

/**
 * @title TransferOwnershipScript
 * @dev 权限转移脚本: 将 MC 和 TaxDistributor 的 owner 转移给新地址
 *
 * 环境变量:
 * - PRIVATE_KEY: 当前 owner 的私钥
 * - MC_ADDRESS: MC 合约地址
 * - NEW_OWNER: 新 owner 地址
 * - TAX_DISTRIBUTOR_ADDRESS: TaxDistributor 合约地址
 * - TAX_WALLET_1: 税收钱包1
 * - TAX_WALLET_2: 税收钱包2
 * - TAX_WALLET_3: 税收钱包3
 *
 * 运行命令:
 * forge script script/mc/TransferOwnership.s.sol --rpc-url bsc_mainnet --broadcast
 */
contract TransferOwnershipScript is Script {
    function run() external {
        // 从环境变量读取配置
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address mcAddress = vm.envAddress("MC_ADDRESS");
        address newOwner = vm.envAddress("NEW_OWNER");
        address taxDistributorAddress = vm.envAddress("TAX_DISTRIBUTOR_ADDRESS");
        address taxWallet1 = vm.envAddress("TAX_WALLET_1");
        address taxWallet2 = vm.envAddress("TAX_WALLET_2");
        address taxWallet3 = vm.envAddress("TAX_WALLET_3");

        // 从私钥派生当前 owner 地址
        address currentOwner = vm.addr(ownerPrivateKey);

        // 加载合约
        MC mc = MC(mcAddress);

        console.log(unicode"=== 权限转移脚本 ===");
        console.log(unicode"MC 合约:", mcAddress);
        console.log(unicode"新 Owner:", newOwner);
        console.log(unicode"TaxDistributor 合约:", taxDistributorAddress);
        console.log(unicode"税收钱包1:", taxWallet1);
        console.log(unicode"税收钱包2:", taxWallet2);
        console.log(unicode"税收钱包3:", taxWallet3);

        TaxDistributor distributor = TaxDistributor(taxDistributorAddress);

        bool isMcOwner = mc.owner() == currentOwner;
        bool isDistributorOwner = distributor.owner() == currentOwner;

        console.log(unicode"当前调用者:", currentOwner);
        console.log(unicode"MC 当前 Owner:", mc.owner());
        console.log(unicode"TaxDistributor 当前 Owner:", distributor.owner());

        vm.startBroadcast(ownerPrivateKey);

        // 1. 转移代币余额
        uint256 tokenBalance = mc.balanceOf(currentOwner);
        if (tokenBalance > 0) {
            console.log(unicode"转移代币余额...");
            mc.transfer(newOwner, tokenBalance);
            console.log(unicode"代币余额已转移:", tokenBalance / 1 ether);
        }

        // 2. 转移 MC 合约 owner (仅当有权限时)
        if (isMcOwner) {
            console.log(unicode"转移 MC 合约权限...");
            mc.transferOwnership(newOwner);
            console.log(unicode"MC 合约权限已转移");
        } else {
            console.log(unicode"跳过 MC 合约权限转移 (无权限)");
        }

        // 3. 设置税收钱包并转移 TaxDistributor 合约 owner (仅当有权限时)
        if (isDistributorOwner) {
            console.log(unicode"设置 TaxDistributor 税收钱包...");
            distributor.setTaxWallets(taxWallet1, taxWallet2, taxWallet3);
            console.log(unicode"税收钱包已设置");

            console.log(unicode"转移 TaxDistributor 合约权限...");
            distributor.transferOwnership(newOwner);
            console.log(unicode"TaxDistributor 合约权限已转移");
        } else {
            console.log(unicode"跳过 TaxDistributor 操作 (无权限)");
        }

        vm.stopBroadcast();

        // 验证结果
        console.log(unicode"\n=== 验证结果 ===");
        console.log(unicode"MC Owner:", mc.owner());
        console.log(unicode"TaxDistributor Owner:", distributor.owner());
        console.log(unicode"新 Owner 代币余额:", mc.balanceOf(newOwner) / 1 ether);

        console.log(unicode"\n=== 权限转移完成 ===");
    }
}
