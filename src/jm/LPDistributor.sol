// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPancakePair.sol";
import "./JMBToken.sol";

/**
 * @title LPDistributor
 * @dev LP分红管理合约 - 无权限设计
 */
contract LPDistributor is Ownable {
    // JM代币地址
    address public jmToken;
    // LP Token地址(PancakePair)
    address public lpPair;
    // JMB凭证代币
    JMBToken public jmbToken;
    // WBNB地址
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // 最小LP价值门槛(100 USD等值BNB, 按0.03USD价格约3.33BNB)
    uint256 public constant MIN_LP_THRESHOLD = 3 ether; // 约3BNB,约100U

    // 用户质押的LP数量
    mapping(address => uint256) public stakedLP;
    // 用户总质押LP价值(BNB计价,存入时记录)
    mapping(address => uint256) public stakedLPValue;

    // 分红累积: 每个JMB单位累积的BNB
    uint256 public accBNBPerJMB;
    // 用户上次结算时的accBNBPerJMB
    mapping(address => uint256) public userAccBNBPerJMB;
    // 用户待领取的分红(BNB)
    mapping(address => uint256) public pendingReward;
    // 用户已解锁可领取的分红(BNB)
    mapping(address => uint256) public unlockedReward;
    // 用户需要购买的BNB金额才能解锁
    mapping(address => uint256) public needBuyToUnlock;
    // 用户已购买的BNB金额(累计)
    mapping(address => uint256) public boughtAmount;

    // 总质押JMB数量
    uint256 public totalStakedJMB;

    // 事件
    event LPStaked(address indexed user, uint256 lpAmount, uint256 jmbAmount);
    event LPUnstaked(address indexed user, uint256 lpAmount, uint256 jmbAmount);
    event RewardClaimed(address indexed user, uint256 amount);
    event BuyRecorded(address indexed user, uint256 bnbAmount);
    event BnbDistributed(uint256 amount);

    constructor(address _jmToken, address _lpPair, address _jmbToken) Ownable(msg.sender) {
        jmToken = _jmToken;
        lpPair = _lpPair;
        jmbToken = JMBToken(_jmbToken);
    }

    /**
     * @dev 接收BNB分红
     */
    receive() external payable {
        if (msg.value > 0) {
            _distributeBNB();
        }
    }

    /**
     * @dev 分发BNB到LP持有者 - 任何人可调用
     */
    function distributeBNB() external payable {
        require(msg.value > 0, "No BNB");
        _distributeBNB();
    }

    /**
     * @dev 内部分发逻辑
     */
    function _distributeBNB() internal {
        if (totalStakedJMB == 0) return;

        // 累加分红: 每JMB分得多少BNB
        accBNBPerJMB += (msg.value * 1e18) / totalStakedJMB;

        emit BnbDistributed(msg.value);
    }

    /**
     * @dev 获取LP对应的BNB价值
     */
    function _getLPBNBValue(uint256 lpAmount) internal view returns (uint256) {
        IPancakePair pair = IPancakePair(lpPair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 totalSupply = pair.totalSupply();

        if (totalSupply == 0) return 0;

        // 判断哪个是BNB
        address token0 = pair.token0();
        uint256 bnbReserve = token0 == WBNB ? reserve0 : reserve1;

        // LP对应的BNB价值
        return (lpAmount * bnbReserve) / totalSupply;
    }

    /**
     * @dev 获取当前JM价格(BNB计价)
     */
    function _getJMPriceInBNB() internal view returns (uint256) {
        IPancakePair pair = IPancakePair(lpPair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        address token0 = pair.token0();
        if (token0 == WBNB) {
            // reserve0是BNB, reserve1是JM
            if (reserve1 == 0) return 0;
            return (uint256(reserve0) * 1e18) / uint256(reserve1);
        } else {
            // reserve0是JM, reserve1是BNB
            if (reserve0 == 0) return 0;
            return (uint256(reserve1) * 1e18) / uint256(reserve0);
        }
    }

    /**
     * @dev 结算用户分红
     */
    function _updateReward(address user) internal {
        uint256 jmbBalance = stakedLP[user]; // 1:1对应
        if (jmbBalance == 0) {
            userAccBNBPerJMB[user] = accBNBPerJMB;
            return;
        }

        // 计算新增分红
        uint256 reward = (jmbBalance * (accBNBPerJMB - userAccBNBPerJMB[user])) / 1e18;

        if (reward > 0) {
            pendingReward[user] += reward;
            // 需要购买同等金额才能解锁
            needBuyToUnlock[user] += reward;
        }

        userAccBNBPerJMB[user] = accBNBPerJMB;
    }

    /**
     * @dev 质押LP Token获得JMB凭证
     */
    function stakeLP(uint256 amount) external {
        require(amount > 0, "Zero amount");

        // 先结算已有分红
        _updateReward(msg.sender);

        // 计算LP的BNB价值
        uint256 bnbValue = _getLPBNBValue(amount);
        require(bnbValue >= MIN_LP_THRESHOLD, "LP value too low");

        // 转移LP Token到合约
        IPancakePair pair = IPancakePair(lpPair);
        require(pair.transferFrom(msg.sender, address(this), amount), "Transfer LP failed");

        // 记录质押
        stakedLP[msg.sender] += amount;
        stakedLPValue[msg.sender] += bnbValue;
        totalStakedJMB += amount;

        // 铸造JMB凭证(1:1)
        jmbToken.mint(msg.sender, amount);

        emit LPStaked(msg.sender, amount, amount);
    }

    /**
     * @dev 解押LP Token,销毁JMB
     */
    function unstakeLP(uint256 amount) external {
        require(amount > 0, "Zero amount");
        require(stakedLP[msg.sender] >= amount, "Insufficient staked");

        // 先结算分红
        _updateReward(msg.sender);

        // 减少质押
        stakedLP[msg.sender] -= amount;
        totalStakedJMB -= amount;

        // 销毁JMB
        jmbToken.burn(msg.sender, amount);

        // 返还LP Token
        IPancakePair pair = IPancakePair(lpPair);
        require(pair.transfer(msg.sender, amount), "Transfer LP failed");

        emit LPUnstaked(msg.sender, amount, amount);
    }

    /**
     * @dev 记录用户购买(由JMToken调用)
     * 如果有已解锁的分红，自动领取
     */
    function recordBuy(address user, uint256 bnbAmount) external {
        require(msg.sender == jmToken, "Only JMToken");

        // 先结算当前分红
        _updateReward(user);

        boughtAmount[user] += bnbAmount;

        // 检查是否可以解锁
        if (needBuyToUnlock[user] > 0 && boughtAmount[user] >= needBuyToUnlock[user]) {
            // 解锁分红
            unlockedReward[user] += pendingReward[user];
            pendingReward[user] = 0;
            needBuyToUnlock[user] = 0;
            boughtAmount[user] = 0; // 重置已购买金额
        }

        // 如果有已解锁的分红，自动转账给用户
        uint256 claimable = unlockedReward[user];
        if (claimable > 0) {
            unlockedReward[user] = 0;
            (bool success, ) = user.call{value: claimable}("");
            require(success, "Auto claim failed");
            emit RewardClaimed(user, claimable);
        }

        emit BuyRecorded(user, bnbAmount);
    }

    /**
     * @dev 领取分红
     */
    function claimReward() external {
        // 先结算
        _updateReward(msg.sender);

        uint256 claimable = unlockedReward[msg.sender];
        require(claimable > 0, "No reward to claim");

        unlockedReward[msg.sender] = 0;

        // 转账BNB
        (bool success, ) = msg.sender.call{value: claimable}("");
        require(success, "BNB transfer failed");

        emit RewardClaimed(msg.sender, claimable);
    }

    /**
     * @dev 查询用户状态
     */
    function getUserInfo(address user) external view returns (
        uint256 stakedLPAmount,
        uint256 pending,
        uint256 unlocked,
        uint256 needBuy,
        uint256 bought
    ) {
        stakedLPAmount = stakedLP[user];

        // 计算当前待领取
        uint256 jmbBalance = stakedLP[user];
        if (jmbBalance > 0) {
            uint256 reward = (jmbBalance * (accBNBPerJMB - userAccBNBPerJMB[user])) / 1e18;
            pending = pendingReward[user] + reward;
        } else {
            pending = pendingReward[user];
        }

        unlocked = unlockedReward[user];
        needBuy = needBuyToUnlock[user];
        bought = boughtAmount[user];
    }

    /**
     * @dev 返回用户当前待解锁分红(包含本轮未结算增量)
     */
    function getPendingReward(address user) external view returns (uint256) {
        uint256 jmbBalance = stakedLP[user];
        if (jmbBalance == 0) return pendingReward[user];
        uint256 reward = (jmbBalance * (accBNBPerJMB - userAccBNBPerJMB[user])) / 1e18;
        return pendingReward[user] + reward;
    }

    /**
     * @dev 紧急提取BNB(仅owner)
     */
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}
