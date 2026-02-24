// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMarking {
    function buy(uint256 _usdtAmount) external;

    function sell(uint256 _d3xaiAmount) external;
}
