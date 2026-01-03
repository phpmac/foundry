// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * 加密合约接口
 */
interface IEncrypt {
    /**
     * 验证SN是否有效
     * @param _snEncrypt SN字符串 未加密,比如 123456
     * @return 是否存在,是否有效
     */
    function validSnDecrypt(
        string memory _snEncrypt
    ) external view returns (bool, bool);

    /**
     * 查询SN是否已使用
     * @param _snEncrypt SN加密数据
     * @return 是否已使用
     */
    function isSnUsed(bytes32 _snEncrypt) external view returns (bool);

    /**
     * 判断SN加密是否存在
     * @param _snEncrypt SN加密数据,比如 0xc888c9ce9e098d5864d3ded6ebcc140a12142263bace3a23a36f9905f12bd64a 这是 123456 加密后的数据
     * @return 是否存在
     */
    function validSnEncrypt(bytes32 _snEncrypt) external view returns (bool);

    /**
     * 批量使用SN
     * @param _snEncrypt SN加密数据数组
     */
    function batchUseSnEncrypt(string[] memory _snEncrypt) external;
}
