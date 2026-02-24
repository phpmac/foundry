// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Invite} from "../../src/bird-points/Invite.sol";

/**
 * @title ReadInviteScript
 * @dev Invite 代理合约: 读取状态
 *
 * 读取状态:
 * forge script script/bird-points/ReadInvite.s.sol --rpc-url eni
 *
 * 环境变量:
 * INVITE_PROXY_ADDRESS - Invite 代理合约地址
 */
contract ReadInviteScript is Script {
    function run() external view {
        address proxyAddress = vm.envAddress("INVITE_PROXY_ADDRESS");
        require(proxyAddress != address(0), unicode"INVITE_PROXY_ADDRESS 未设置");

        Invite invite = Invite(proxyAddress);

        console.log(unicode"=== Invite 合约状态 ===");
        console.log(unicode"代理地址:", proxyAddress);

        // 读取权限角色
        bytes32 defaultAdminRole = invite.DEFAULT_ADMIN_ROLE();
        bytes32 whitelist = invite.WHITELIST();

        console.log(unicode"\n=== 权限角色 ===");
        console.log(unicode"默认管理员角色:", vm.toString(defaultAdminRole));
        console.log(unicode"白名单角色:", vm.toString(whitelist));

        // 测试邀请关系
        address testUser1 = 0x1111111111111111111111111111111111111111;
        address testUser2 = 0x2222222222222222222222222222222222222222;

        console.log(unicode"\n=== 邀请关系测试 ===");
        console.log(unicode"测试用户1 上级:", invite.getParent(testUser1));
        console.log(unicode"测试用户2 上级:", invite.getParent(testUser2));

        // 测试地址有效性
        console.log(unicode"\n=== 地址有效性 ===");
        console.log(unicode"测试用户1 是否有效:", invite.isValidAddress(testUser1));
        console.log(unicode"测试用户2 是否有效:", invite.isValidAddress(testUser2));

        console.log(unicode"\n========================");
    }
}
