// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {BuyHashNft} from "../../src/bird-points/BuyHashNft.sol";

/**
 * @title UpgradeBuyHashNftScript
 * @dev BuyHashNft 合约升级脚本
 *
 * 运行命令:
 * forge script script/bird-points/UpgradeBuyHashNft.s.sol --rpc-url eni --broadcast
 *
 * 环境变量:
 * - PRIVATE_KEY: 升级者私钥 (需要 DEFAULT_ADMIN_ROLE)
 * - NFT_SALE_PROXY_ADDRESS: BuyHashNft 代理合约地址
 */
contract UpgradeBuyHashNftScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address buyHashNftProxy = vm.envAddress("NFT_SALE_PROXY_ADDRESS");

        console.log(unicode"=== BuyHashNft 升级配置 ===");
        console.log(unicode"升级者地址:", deployer);
        console.log(unicode"代理合约地址:", buyHashNftProxy);
        console.log(unicode"================\n");

        require(buyHashNftProxy != address(0), unicode"NFT_SALE_PROXY_ADDRESS 未设置");

        vm.startBroadcast(deployerPrivateKey);

        // 部署新实现合约
        console.log(unicode"部署新的 BuyHashNft 实现合约...");
        BuyHashNft newImpl = new BuyHashNft();
        console.log(unicode"新实现合约地址:", address(newImpl));

        // 升级代理
        console.log(unicode"升级代理...");
        BuyHashNft proxy = BuyHashNft(buyHashNftProxy);
        proxy.upgradeToAndCall(address(newImpl), "");
        console.log(unicode"升级完成");

        // 健康检查
        console.log(unicode"执行健康检查...");
        proxy.healthcheck();
        console.log(unicode"健康检查通过");

        vm.stopBroadcast();

        console.log(unicode"\n=== 升级摘要 ===");
        console.log(unicode"新实现合约:", address(newImpl));
    }
}