// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Invite} from "../../src/bird-points/Invite.sol";

/**
 * @title DeployInviteScript
 * @dev Invite 合约部署脚本: 部署可升级的 Invite 合约
 *
 * 运行命令:
 * forge script script/bird-points/DeployInvite.s.sol --rpc-url eni --broadcast
 */
contract DeployInviteScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log(unicode"=== 配置检查 ===");
        console.log(unicode"部署者地址:", deployer);
        console.log(unicode"部署者 ETH 余额:", deployer.balance / 1e18);
        console.log(unicode"================\n");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 Invite 实现合约
        console.log(unicode"部署 Invite 实现合约...");
        Invite inviteImpl = new Invite();
        console.log(unicode"实现合约地址:", address(inviteImpl));

        // 初始化数据
        bytes memory initData = abi.encodeWithSelector(
            Invite.initialize.selector,
            deployer
        );

        // 部署代理合约
        console.log(unicode"部署 ERC1967Proxy 代理合约...");
        ERC1967Proxy proxy = new ERC1967Proxy(address(inviteImpl), initData);
        console.log(unicode"代理合约地址:", address(proxy));

        Invite invite = Invite(address(proxy));

        // 验证
        console.log(unicode"管理员地址:", invite.hasRole(invite.DEFAULT_ADMIN_ROLE(), deployer));
        console.log(unicode"部署者是否有效邀请人:", invite.isValidAddress(deployer));

        vm.stopBroadcast();

        console.log(unicode"\n=== 部署摘要 ===");
        console.log(unicode"实现合约:", address(inviteImpl));
        console.log(unicode"代理合约 (使用此地址):", address(proxy));
        console.log(unicode"管理员:", deployer);
    }
}
