// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * IInvite
 */
interface IInvite {
    /**
     * 绑定父级事件
     */
    event BindParent(address indexed member, address indexed parent);

    /**
     * 获取指定成员的上级地址
     * @param member 要查询的成员地址
     * @return parent 返回该成员的上级地址
     */
    function getParent(address member) external view returns (address parent);

    /**
     * 由合约代表成员绑定上级
     * @param member 要绑定上级的成员地址
     * @param parent 要绑定的上级地址
     */
    function bindParentFrom(address member, address parent) external;

    /**
     * 成员直接绑定上级
     * @param parent 要绑定的上级地址
     */
    function bindParent(address parent) external;

    /**
     * 检查地址是否为有效的邀请地址
     * @param account 要检查的地址
     * @return 如果是有效的邀请地址返回true,否则返回false
     */
    function isValidAddress(address account) external view returns (bool);
}
