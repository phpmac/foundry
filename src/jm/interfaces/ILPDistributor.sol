// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILPDistributor {
    function distributeBNB() external payable;
    function recordBuy(address user, uint256 bnbAmount) external;
    function getPendingReward(address user) external view returns (uint256);
    function claimReward() external;
    function stakeLP(uint256 amount) external;
    function unstakeLP(uint256 amount) external;
}
