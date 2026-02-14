// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILPDistributor {
    function notifyRewardInWBNB(uint256 amount) external;
    function recordBuy(address user, uint256 bnbAmount) external;
    function setBalance(address account, uint256 newLPBalance) external;
    function excludeFromDividends(address account) external;
    function getPendingReward(address user) external view returns (uint256);
    function claimReward() external;
}
