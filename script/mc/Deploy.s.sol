// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MC} from "../../src/mc/MC.sol";
import {TaxDistributor} from "../../src/mc/TaxDistributor.sol";

contract DeployScript is Script {
    // BSC 主网地址
    address public constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    function run() external {
        // 获取部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 从环境变量读取税收钱包地址
        address taxWallet1 = vm.envAddress("TAX_WALLET_1");
        address taxWallet2 = vm.envAddress("TAX_WALLET_2");
        address taxWallet3 = vm.envAddress("TAX_WALLET_3");

        require(taxWallet1 != address(0), "TAX_WALLET_1 not set");
        require(taxWallet2 != address(0), "TAX_WALLET_2 not set");
        require(taxWallet3 != address(0), "TAX_WALLET_3 not set");

        // 1. 部署 MC 合约
        console.log("Deploying MC token...");
        MC mc = new MC(taxWallet1, taxWallet2, taxWallet3, ROUTER);
        console.log("MC deployed at:", address(mc));

        // 2. 部署 TaxDistributor 合约
        console.log("Deploying TaxDistributor...");
        TaxDistributor distributor = new TaxDistributor(
            address(mc),
            ROUTER,
            taxWallet1,
            taxWallet2,
            taxWallet3
        );
        console.log("TaxDistributor deployed at:", address(distributor));

        // 3. 绑定 TaxDistributor
        console.log("Setting TaxDistributor...");
        mc.setTaxDistributor(address(distributor));
        console.log("TaxDistributor set successfully");

        // 4. 开启交易 (可选)
        // mc.setTradingEnabled(true);
        // console.log("Trading enabled");

        vm.stopBroadcast();

        // 输出部署信息
        console.log("\n=== Deployment Summary ===");
        console.log("MC Token:", address(mc));
        console.log("TaxDistributor:", address(distributor));
        console.log("Owner:", vm.addr(deployerPrivateKey));
        console.log("Tax Wallet 1:", taxWallet1);
        console.log("Tax Wallet 2:", taxWallet2);
        console.log("Tax Wallet 3:", taxWallet3);
    }
}
