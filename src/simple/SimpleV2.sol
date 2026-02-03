// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Simple} from "./Simple.sol";

/**
 * 简单合约V2(升级版本示例)
 *
 * 部署流程:
 * 1. 部署新实现合约
 * 2. 通过 ProxyAdmin 调用 upgradeAndCall 升级
 */
contract SimpleV2 is Simple {
    uint256 public version;

    /**
     * 升级后的初始化(reinitializer)
     */
    function initializeV2() public reinitializer(2) {
        version = 2;
    }

    /**
     * V2新增的方法
     */
    function getVersion() public view returns (uint256) {
        return version;
    }
}
