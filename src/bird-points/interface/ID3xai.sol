// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * ID3xai
 */
interface ID3xai is IERC20 {
    /**
     * 获得 d3xai 价格
     * @return 价格
     */
    function price() external view returns (uint256);

    /**
     * 销毁底池代币
     * @param amount 销毁数量
     */
    function recycle(uint256 amount) external;

    /**
     * 获取用户最后买入时间
     * @param user 用户地址
     * @return 最后买入时间戳
     */
    function lastBuy(address user) external view returns (uint256);

    /**
     * 获取用户是否在白名单
     * @param user 用户地址
     * @return 是否白名单
     */
    function whitelist(address user) external view returns (bool);

    /**
     * 是否触发熔断
     * @return 是否熔断
     */
    function isBreakthrough() external view returns (bool);

    /**
     * 销毁指定用户代币(需要 SELL_ROLE)
     * @param user 用户地址
     * @param amount 销毁数量
     */
    function burnFrom(address user, uint256 amount) external;
}
