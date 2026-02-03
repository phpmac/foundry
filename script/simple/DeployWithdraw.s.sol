// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Withdraw} from "../../src/mc/Withdraw.sol";

/**
 * @title DeployWithdrawScript
 * @dev Withdraw 合约部署脚本: 部署可升级的 Withdraw 合约
 *
 * 运行命令:
 * forge script script/mc/DeployWithdraw.s.sol --broadcast
 */
contract DeployWithdrawScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log(unicode"=== 配置检查 ===");
        console.log(unicode"部署者地址:", deployer);

        address withdrawalSignAddress = vm.envAddress("WITHDRAW_SIGN_ADDRESS");
        require(
            withdrawalSignAddress != address(0),
            unicode"WITHDRAW_SIGN_ADDRESS 未设置"
        );
        console.log(unicode"提现签名地址:", withdrawalSignAddress);
        console.log(unicode"================\n");

        vm.startBroadcast(deployerPrivateKey);

        console.log(unicode"部署 Withdraw 实现合约...");
        Withdraw withdrawImpl = new Withdraw();
        console.log(unicode"实现合约地址:", address(withdrawImpl));

        bytes memory initData = abi.encodeWithSelector(
            Withdraw.initialize.selector,
            withdrawalSignAddress
        );

        console.log(unicode"部署 ERC1967Proxy 代理合约...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(withdrawImpl), initData);
        console.log(unicode"代理合约地址:", address(proxy));

        Withdraw withdraw = Withdraw(address(proxy));

        console.log(unicode"执行健康检查...");
        withdraw.healthcheck();
        console.log(unicode"健康检查通过");

        console.log(unicode"提现签名地址:", withdraw.withdrawalSignAddress());
        console.log(unicode"管理员地址:", deployer);
        console.log(unicode"是否暂停:", withdraw.isPause());

        vm.stopBroadcast();

        console.log(unicode"\n=== 部署摘要 ===");
        console.log(unicode"实现合约:", address(withdrawImpl));
        console.log(unicode"代理合约 (使用此地址):", address(proxy));
        console.log(unicode"管理员:", deployer);
        console.log(unicode"提现签名地址:", withdrawalSignAddress);
    }
}
