// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 运行命令:
// forge test --match-path test/bird-points/* -vvv

import {Invite} from "../../src/bird-points/Invite.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

event BindParent(address indexed member, address indexed parent);

contract BirdPointsTest is Test {
    Invite public invite;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    // 测试网 chainId (BSC testnet)
    uint256 public constant TEST_CHAIN_ID = 97;

    function setUp() public {
        // 设置测试网 chainId - 必须在最前面
        vm.chainId(TEST_CHAIN_ID);

        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        // 部署 Invite 实现合约
        Invite inviteImpl = new Invite();

        // 部署代理合约
        bytes memory initData = abi.encodeWithSelector(Invite.initialize.selector, owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(inviteImpl), initData);
        invite = Invite(address(proxy));

        console.log(unicode"=== 部署 Invite ===");
        console.log(unicode"Invite 地址:", address(invite));
    }

    // ============ Invite 测试 ============

    function test_InviteDeployment() public view {
        // 验证部署者被设为有效邀请人
        assertTrue(invite.isValidAddress(owner));
        assertEq(invite.getParent(owner), address(0x01));

        console.log(unicode"Invite 部署测试通过");
    }

    function test_BindParentByWhitelist() public {
        // 验证 alice 初始没有上级
        assertEq(invite.getParent(alice), address(0));

        // 白名单用户绑定关系
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);

        // 验证绑定关系
        assertEq(invite.getParent(alice), owner);
        console.log(unicode"白名单绑定关系测试通过");
    }

    function test_BindParentByUser() public {
        // 用户自己绑定邀请人
        vm.prank(alice);
        invite.bindParent(bob);

        // 验证绑定关系
        assertEq(invite.getParent(alice), bob);
        console.log(unicode"用户自主绑定测试通过");
    }

    function test_GetParent() public {
        // 设置绑定关系
        vm.prank(owner);
        invite.bindParentFrom(alice, charlie);

        // 获取上级
        address parent = invite.getParent(alice);
        assertEq(parent, charlie);

        // 未绑定用户
        address noParent = invite.getParent(bob);
        assertEq(noParent, address(0));

        console.log(unicode"获取上级测试通过");
    }

    function test_EnableInviter() public {
        // 启用邀请人
        vm.prank(owner);
        invite.enableInviter(alice);

        // 验证 alice 成为有效邀请人
        assertTrue(invite.isValidAddress(alice));
        assertEq(invite.getParent(alice), address(0x01));

        console.log(unicode"启用邀请人测试通过");
    }

    function test_SetParent() public {
        // 初始绑定
        vm.prank(owner);
        invite.bindParentFrom(alice, bob);

        // 修改上级
        vm.prank(owner);
        invite.setParent(alice, charlie);

        assertEq(invite.getParent(alice), charlie);
        console.log(unicode"修改上级测试通过");
    }

    function test_InvitePermissions() public view {
        // 验证 owner 有 DEFAULT_ADMIN_ROLE
        bytes32 defaultAdminRole = invite.DEFAULT_ADMIN_ROLE();
        assertTrue(invite.hasRole(defaultAdminRole, owner));

        // 验证 owner 有 WHITELIST 角色
        bytes32 whitelist = invite.WHITELIST();
        assertTrue(invite.hasRole(whitelist, owner));

        // 验证普通用户没有权限
        assertFalse(invite.hasRole(defaultAdminRole, alice));
        assertFalse(invite.hasRole(whitelist, alice));
        console.log(unicode"Invite 权限测试通过");
    }

    function test_FullIntegration() public {
        // 绑定邀请关系
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);

        assertEq(invite.getParent(alice), owner);

        // 管理员给 bob 绑定关系
        vm.prank(owner);
        invite.bindParentFrom(bob, alice);

        assertEq(invite.getParent(bob), alice);

        console.log(unicode"集成测试通过");
        console.log(unicode"Alice 上级:", invite.getParent(alice));
        console.log(unicode"Bob 上级:", invite.getParent(bob));
    }
}
