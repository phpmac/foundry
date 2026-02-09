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
 * 运行命令:
 * forge script script/mc/TransferOwnership.s.sol --rpc-url bsc_mainnet --broadcast
 */
contract TransferOwnershipScript is Script {
    // MC 合约地址
    address public constant MC_ADDRESS =
        0xb531613381ccE69DACdfe3693570f8cbf8BDA81f;

    // TaxDistributor 合约地址 (如果有的话, 需要填写)
    address public constant TAX_DISTRIBUTOR_ADDRESS = address(0);

    // 新 Owner 地址
    address public constant NEW_OWNER =
        0x348d62c4134be9B03E324B1d1A981627EAF47695;

    function run() external {
        // 获取 owner 私钥, 并从私钥派生当前 owner 地址
        uint256 ownerPrivateKey = vm.envUint("PRIVATE_KEY");
        address CURRENT_OWNER = vm.addr(ownerPrivateKey);

        // 加载合约
        MC mc = MC(MC_ADDRESS);

        console.log(unicode"=== 权限转移脚本 ===");
        console.log(unicode"MC 合约:", MC_ADDRESS);
        console.log(unicode"当前 Owner:", mc.owner());
        console.log(unicode"新 Owner:", NEW_OWNER);

        // 检查当前 owner
        require(mc.owner() == CURRENT_OWNER, "Not current owner");

        // 获取当前 owner 的代币余额
        uint256 tokenBalance = mc.balanceOf(CURRENT_OWNER);
        console.log(unicode"当前 Owner 代币余额:", tokenBalance / 1 ether);

        vm.startBroadcast(ownerPrivateKey);

        // 1. 转移代币余额
        if (tokenBalance > 0) {
            console.log(unicode"转移代币余额...");
            mc.transfer(NEW_OWNER, tokenBalance);
            console.log(unicode"代币余额已转移:", tokenBalance / 1 ether);
        }

        // 2. 转移 MC 合约 owner
        console.log(unicode"转移 MC 合约权限...");
        mc.transferOwnership(NEW_OWNER);
        console.log(unicode"MC 合约权限已转移");

        // 3. 转移 TaxDistributor 合约 owner (如果有)
        if (TAX_DISTRIBUTOR_ADDRESS != address(0)) {
            console.log(unicode"转移 TaxDistributor 合约权限...");
            TaxDistributor distributor = TaxDistributor(
                TAX_DISTRIBUTOR_ADDRESS
            );
            distributor.transferOwnership(NEW_OWNER);
            console.log(unicode"TaxDistributor 合约权限已转移");
        }

        vm.stopBroadcast();

        // 验证结果
        console.log(unicode"\n=== 验证结果 ===");
        console.log(unicode"MC 新 Owner:", mc.owner());
        console.log(
            unicode"新 Owner 代币余额:",
            mc.balanceOf(NEW_OWNER) / 1 ether
        );

        console.log(unicode"\n=== 权限转移完成 ===");
    }
}
