// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ILAXOToken {
    function isReachedMaxBurn() external view returns (bool);
    function addUserQuota(address user, uint256 amount) external;
}