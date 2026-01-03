// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * PancakeSwap工厂接口
 */
interface IPancakeFactory {
    /**
     * 创建交易对
     * @param _tokenA 代币A
     * @param _tokenB 代币B
     * @return 交易对地址
     */
    function createPair(
        address _tokenA,
        address _tokenB
    ) external returns (address);

    /**
     * 查询交易对
     * @param _tokenA 代币A
     * @param _tokenB 代币B
     * @return 交易对地址
     */
    function getPair(
        address _tokenA,
        address _tokenB
    ) external view returns (address);
}
