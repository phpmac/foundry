// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IStaking {
    // ============ Structs ============
    struct Record {
        uint40 stakeTime;
        uint160 amount;
        uint8 stakeIndex;
        uint40 unstakeTime;
        uint160 reward;
        uint40 restakeTime;
    }

    struct Config {
        uint256 rate;
        uint40 day;
        uint40 ttl;
    }

     // ============ Events ============
    event Staked(
        address indexed user,
        uint160 amount,
        uint40 timestamp,
        uint256 index,
        uint40 stakeTime
    );

    event RewardPaid(
        address indexed user,
        uint160 reward,
        uint40 timestamp,
        uint256 index
    );

    event Unstaked(
        address indexed user,
        uint160 amount,
        uint40 timestamp,
        uint256 index,
        uint160 reward,
        uint40 ttl
    );

    event Restaked(address indexed user, uint40 timestamp, uint256 index);

    event Transfer(address indexed from, address indexed to, uint256 amount);

    // ============ View Functions ============
    function userOneDayStaked(address user) external view returns (bool);
    function getStakeRecord(address user, uint256 index) external view returns (Record memory);

    // ============ Core Functions (Called by Queue) ============
    function stakeFor(address user, uint160 amount, uint8 stakeIndex) external;
    function unstakeFor(address user, uint256 index) external returns (uint256 actualAmount);
    function restakeFor(address user, uint256 _index, uint160 _amount, uint8 _stakeIndex) external;
    function claimFor(address user, uint256 _index) external;
}