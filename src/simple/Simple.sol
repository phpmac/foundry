// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * 简单合约
 *
 */
contract Simple is AccessControlUpgradeable {
    bool public enable; // 是否启用

    // 系统开关
    modifier onlyEnable() {
        require(enable, "System is not enabled");
        _;
    }

    // ! 只允许EOA调用,防止合约调用导致的攻击,例如闪电贷
    modifier onlyEOA() {
        require(tx.origin == _msgSender(), "EOA");
        _;
    }

    /**
     * ! 禁用实现合约的初始化, 防止攻击者直接初始化实现合约
     * 参考: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable#initializing_the_implementation_contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * 初始化
     */
    function initialize() public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        setEnable(true);

        todo();
    }

    /**
     * 管理员设置系统开关
     * @param _enable 是否启用
     */
    function setEnable(bool _enable) public onlyRole(DEFAULT_ADMIN_ROLE) {
        enable = _enable;
    }

    /**
     * 管理员执行自动化配置
     * ! 有一些不能写在里面,比如随时改动的手续费,只能写入固定的,或者判断没有初始化再初始化
     */
    function todo() public onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * 健康检查
     */
    function healthcheck() public view {}
}
