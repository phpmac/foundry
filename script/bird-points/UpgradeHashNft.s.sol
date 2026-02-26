// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {HashNft} from "../../src/bird-points/HashNft.sol";

/**
 * @title UpgradeHashNftScript
 * @dev HashNft 合约升级脚本
 *
 * 运行命令:
 * forge script script/bird-points/UpgradeHashNft.s.sol --rpc-url eni --broadcast
 *
 * 环境变量:
 * - PRIVATE_KEY: 升级者私钥 (需要 DEFAULT_ADMIN_ROLE)
 * - HASH_RATE_NFT_PROXY_ADDRESS: HashNft 代理合约地址
 */
contract UpgradeHashNftScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address hashNftProxy = vm.envAddress("HASH_RATE_NFT_PROXY_ADDRESS");

        console.log(unicode"=== HashNft 升级配置 ===");
        console.log(unicode"升级者地址:", deployer);
        console.log(unicode"代理合约地址:", hashNftProxy);
        console.log(unicode"================\n");

        require(hashNftProxy != address(0), unicode"HASH_RATE_NFT_PROXY_ADDRESS 未设置");

        vm.startBroadcast(deployerPrivateKey);

        // 部署新实现合约
        console.log(unicode"部署新的 HashNft 实现合约...");
        HashNft newImpl = new HashNft();
        console.log(unicode"新实现合约地址:", address(newImpl));

        // 升级代理
        console.log(unicode"升级代理...");
        HashNft proxy = HashNft(hashNftProxy);
        proxy.upgradeToAndCall(address(newImpl), "");
        console.log(unicode"升级完成");

        vm.stopBroadcast();

        console.log(unicode"\n=== 升级摘要 ===");
        console.log(unicode"新实现合约:", address(newImpl));
    }
}