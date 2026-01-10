// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILAXToken
 * @notice LAX Token 接口，继承 IERC20 并添加特有函数
 */
interface ILAXToken is IERC20 {
    function getYesterdayCloseReserveU() external view returns (uint112);
    function getCurrentReserveU() external view returns (uint112);
    function uniswapV2Pair() external view returns (address);
    function recycle(uint256 amount) external;
}