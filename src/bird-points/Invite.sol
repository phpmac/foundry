// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IInvite} from "./interface/IInvite.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Invite
 * @dev 邀请关系管理合约 (可升级)
 */
contract Invite is IInvite, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant WHITELIST = keccak256("WHITELIST");

    mapping(address => address) private inviteMap;

    /**
     * ! 禁用实现合约的初始化, 防止攻击者直接初始化实现合约
     * 参考: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable#initializing_the_implementation_contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * UUPS 升级授权
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * 初始化合约
     * @param _member  管理员地址
     */
    function initialize(address _member) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(WHITELIST, _msgSender());
        enableInviter(_member);
    }

    /**
     * 管理员设置 绑定邀请关系
     * @param _member  被邀请人地址
     * @param _parent  邀请人地址
     */
    function bindParentFrom(
        address _member,
        address _parent
    ) public override onlyRole(WHITELIST) {
        _bindParent(_member, _parent);
    }

    /**
     * 绑定邀请关系
     * @param _member  被邀请人地址
     * @param _parent 邀请人地址
     */
    function _bindParent(address _member, address _parent) internal {
        // 叫取消限制
        // if (!isValidAddress(_parent)) revert("InvalidAddress");
        if (block.chainid != 97) {
            if (inviteMap[_member] != address(0))
                revert("InvalidInvitationAddress");
        }
        inviteMap[_member] = _parent;
        emit BindParent(_member, _parent);
    }

    /**
     * 绑定邀请关系
     * @param _parent  邀请人地址
     */
    function bindParent(address _parent) public {
        _bindParent(msg.sender, _parent);
    }

    /**
     * 获取邀请人地址
     * @param _member  被邀请人地址
     * @return parent  邀请人地址
     */
    function getParent(
        address _member
    ) public view override returns (address parent) {
        return inviteMap[_member];
    }

    /**
     * 校验地址是否有效
     * @param _parent  被校验的地址
     * @return bool  是否有效
     */
    function isValidAddress(address _parent) public view returns (bool) {
        return inviteMap[_parent] != address(0) || _parent == address(0x01);
    }

    /**
     * 设置用户上级地址
     * @param _member  被设置用户地址
     * @param _parent  上级地址
     */
    function setParent(
        address _member,
        address _parent
    ) public onlyRole(WHITELIST) {
        inviteMap[_member] = _parent;
        emit BindParent(_member, _parent);
    }

    /**
     * 管理员设置 启用邀请人
     * @param _member  被启用邀请人地址
     */
    function enableInviter(address _member) public onlyRole(WHITELIST) {
        inviteMap[_member] = address(0x01);
        emit BindParent(_member, address(0x01));
    }
}
