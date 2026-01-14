// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ITaxDistributor
 * @dev 税收分发合约接口
 */
interface ITaxDistributor {
    /**
     * @dev 分发税收：将MC swap成USDT并分发给各钱包
     */
    function distributeTax() external;
}
