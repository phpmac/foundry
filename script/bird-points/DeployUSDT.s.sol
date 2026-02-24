// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SimpleToken} from "../../src/simple/SimpleToken.sol";

/**
 * @title DeployUSDTScript
 * @dev SimpleToken (USDT) 部署脚本: 部署可升级的代币合约
 *
 * 运行命令:
 * forge script script/bird-points/DeployUSDT.s.sol --rpc-url eni --broadcast
 */
contract DeployUSDTScript is Script {
    // 代币参数
    string constant TOKEN_NAME = "USDT";
    string constant TOKEN_SYMBOL = "USDT";
    uint256 constant TOKEN_AMOUNT = 1e8 * 1e18; // 1亿

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log(unicode"=== 配置检查 ===");
        console.log(unicode"部署者地址:", deployer);
        console.log(unicode"部署者 ETH 余额:", deployer.balance / 1e18);
        console.log(unicode"代币名称:", TOKEN_NAME);
        console.log(unicode"代币符号:", TOKEN_SYMBOL);
        console.log(unicode"代币总量:", TOKEN_AMOUNT / 1e18);
        console.log(unicode"================\n");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 SimpleToken 实现合约
        console.log(unicode"部署 SimpleToken 实现合约...");
        SimpleToken tokenImpl = new SimpleToken();
        console.log(unicode"实现合约地址:", address(tokenImpl));

        // 初始化数据
        bytes memory initData = abi.encodeWithSelector(
            SimpleToken.initialize.selector,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_AMOUNT
        );

        // 部署代理合约
        console.log(unicode"部署 ERC1967Proxy 代理合约...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(tokenImpl), initData);
        console.log(unicode"代理合约地址:", address(proxy));

        SimpleToken token = SimpleToken(address(proxy));

        // 验证
        console.log(unicode"代币名称:", token.name());
        console.log(unicode"代币符号:", token.symbol());
        console.log(unicode"代币总量:", token.totalSupply() / 1e18);
        console.log(unicode"部署者余额:", token.balanceOf(deployer) / 1e18);

        vm.stopBroadcast();

        console.log(unicode"\n=== 部署摘要 ===");
        console.log(unicode"实现合约:", address(tokenImpl));
        console.log(unicode"代理合约 (使用此地址):", address(proxy));
        console.log(unicode"管理员:", deployer);
    }
}
