// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Treasury} from "../../src/bird-points/Treasury.sol";

/**
 * @title DeployTreasuryScript
 * @dev Treasury 合约部署脚本: 部署可升级的 Treasury 合约
 *
 * 运行命令:
 * forge script script/bird-points/DeployTreasury.s.sol --rpc-url eni --broadcast
 */
contract DeployTreasuryScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log(unicode"=== 配置检查 ===");
        console.log(unicode"部署者地址:", deployer);
        console.log(unicode"部署者 ETH 余额:", deployer.balance / 1e18);
        console.log(unicode"================\n");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 Treasury 实现合约
        console.log(unicode"部署 Treasury 实现合约...");
        Treasury treasuryImpl = new Treasury();
        console.log(unicode"实现合约地址:", address(treasuryImpl));

        // 初始化数据: Treasury.initialize() 无参数
        bytes memory initData = abi.encodeWithSelector(
            Treasury.initialize.selector
        );

        // 部署代理合约
        console.log(unicode"部署 ERC1967Proxy 代理合约...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(treasuryImpl), initData);
        console.log(unicode"代理合约地址:", address(proxy));

        Treasury treasury = Treasury(address(proxy));

        // 验证
        console.log(unicode"管理员权限:", treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(), deployer));
        console.log(unicode"系统开关状态:", treasury.enable());

        vm.stopBroadcast();

        console.log(unicode"\n=== 部署摘要 ===");
        console.log(unicode"实现合约:", address(treasuryImpl));
        console.log(unicode"代理合约 (使用此地址):", address(proxy));
        console.log(unicode"管理员:", deployer);
    }
}
