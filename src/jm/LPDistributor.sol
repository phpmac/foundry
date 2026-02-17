// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPancakePair.sol";
import "./interfaces/IWBNB.sol";

/**
 * @title LPDistributor
 * @dev LP分红管理合约 - 自动追踪LP持有者模式
 * 核心机制: JMToken在每笔交易后调用setBalance同步用户LP余额,
 * 以LP余额作为分红权重, 无需用户手动质押.
 */
contract LPDistributor is Ownable, IERC20 {
    // JM代币地址
    address public jmToken;
    // LP Token地址(PancakePair)
    address public lpPair;
    // JMB凭证元数据(内置不可转让ERC20)
    string public constant name = "JMB Voucher";
    string public constant symbol = "JMB";
    uint8 public constant decimals = 18;
    // WBNB地址
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // 最小LP价值门槛(0.1 WBNB, 即LP双边价值 >= 0.1 BNB)
    uint256 public constant MIN_LP_THRESHOLD = 0.1 ether;

    // ========== 分红追踪 ==========

    // 用户当前有效LP份额(经过门槛过滤后的值)
    mapping(address => uint256) public shares;
    // 总有效LP份额
    uint256 public totalShares;

    // 分红累积: 每单位share累积的BNB (放大1e18)
    uint256 public accBNBPerShare;
    // 用户上次结算时的accBNBPerShare
    mapping(address => uint256) public userDebt;

    // 用户待领取的分红(BNB) - 已结算但未解锁
    mapping(address => uint256) public pendingReward;
    // 用户已解锁可领取的分红(BNB)
    mapping(address => uint256) public unlockedReward;
    // 用户需要购买的BNB金额才能解锁
    mapping(address => uint256) public needBuyToUnlock;
    // 用户已购买的BNB金额(累计)
    mapping(address => uint256) public boughtAmount;

    // 排除分红的地址(pair/router/dead/合约等)
    mapping(address => bool) public isExcludedFromDividends;

    error NonTransferable();

    // ========== 事件 ==========

    event BalanceUpdated(address indexed account, uint256 oldShares, uint256 newShares);
    event RewardClaimed(address indexed user, uint256 amount);
    event BuyRecorded(address indexed user, uint256 bnbAmount);
    event BnbDistributed(uint256 amount);
    event ExcludedFromDividends(address indexed account);

    constructor(address _jmToken, address _lpPair) Ownable(msg.sender) {
        jmToken = _jmToken;
        lpPair = _lpPair;
    }

    // ========== 接收BNB ==========

    /**
     * @dev 接收BNB分红(WBNB.withdraw触发)
     */
    receive() external payable {
        if (msg.value > 0) {
            _distributeBNBAmount(msg.value);
        }
    }

    /**
     * @dev 内部分发逻辑: 累加全局accBNBPerShare
     */
    function _distributeBNBAmount(uint256 amount) internal {
        if (totalShares == 0) return;
        accBNBPerShare += (amount * 1e18) / totalShares;
        emit BnbDistributed(amount);
    }

    // ========== JMToken调用接口 ==========

    /**
     * @dev JMToken把奖励换成WBNB后通知分发
     */
    function notifyRewardInWBNB(uint256 amount) external {
        require(msg.sender == jmToken, "Only JMToken");
        require(amount > 0, "Zero amount");
        // 将WBNB兑换为BNB, receive()会自动记账分发
        IWBNB(WBNB).withdraw(amount);
    }

    /**
     * @dev 同步用户LP余额 - 由JMToken在每笔交易后调用
     * 核心: 根据pair.balanceOf(account)更新用户的分红份额
     */
    function setBalance(address account, uint256 newLPBalance) external {
        require(msg.sender == jmToken, "Only JMToken");
        if (isExcludedFromDividends[account]) return;

        // 计算LP的BNB价值, 低于门槛则视为0
        uint256 effectiveBalance = newLPBalance;
        if (newLPBalance > 0) {
            uint256 bnbValue = _getLPBNBValue(newLPBalance);
            if (bnbValue < MIN_LP_THRESHOLD) {
                effectiveBalance = 0;
            }
        }

        _setBalance(account, effectiveBalance);
    }

    /**
     * @dev 用户手动同步自己的LP份额
     * 适用于加LP后份额未立即同步的情况
     */
    function syncBalance() external {
        if (isExcludedFromDividends[msg.sender]) return;
        uint256 lpBalance = IPancakePair(lpPair).balanceOf(msg.sender);

        uint256 effectiveBalance = lpBalance;
        if (lpBalance > 0) {
            uint256 bnbValue = _getLPBNBValue(lpBalance);
            if (bnbValue < MIN_LP_THRESHOLD) {
                effectiveBalance = 0;
            }
        }

        _setBalance(msg.sender, effectiveBalance);
    }

    /**
     * @dev 记录用户购买(由JMToken调用), 用于解锁分红
     */
    function recordBuy(address user, uint256 bnbAmount) external {
        require(msg.sender == jmToken, "Only JMToken");

        // 先结算当前分红
        _updateReward(user);

        boughtAmount[user] += bnbAmount;

        // 检查是否可以解锁: 买入金额 >= 分红金额
        if (needBuyToUnlock[user] > 0 && boughtAmount[user] >= needBuyToUnlock[user]) {
            unlockedReward[user] += pendingReward[user];
            pendingReward[user] = 0;
            needBuyToUnlock[user] = 0;
            boughtAmount[user] = 0;
        }

        // 如果有已解锁的分红, 自动转账给用户
        uint256 claimable = unlockedReward[user];
        if (claimable > 0) {
            unlockedReward[user] = 0;
            (bool success, ) = user.call{value: claimable}("");
            require(success, "Auto claim failed");
            emit RewardClaimed(user, claimable);
        }

        emit BuyRecorded(user, bnbAmount);
    }

    // ========== 管理功能 ==========

    /**
     * @dev 排除地址参与分红(pair/router/dead/合约等)
     */
    function excludeFromDividends(address account) external {
        require(msg.sender == owner() || msg.sender == jmToken, "Not authorized");
        if (isExcludedFromDividends[account]) return;

        isExcludedFromDividends[account] = true;

        // 如果该地址有份额, 清零
        if (shares[account] > 0) {
            _setBalance(account, 0);
        }

        emit ExcludedFromDividends(account);
    }

    // ========== 用户功能 ==========

    /**
     * @dev 手动领取已解锁的分红
     */
    function claimReward() external {
        _updateReward(msg.sender);

        uint256 claimable = unlockedReward[msg.sender];
        require(claimable > 0, "No reward to claim");

        unlockedReward[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: claimable}("");
        require(success, "BNB transfer failed");

        emit RewardClaimed(msg.sender, claimable);
    }

    // ========== 内部逻辑 ==========

    /**
     * @dev 更新用户份额, 结算分红, 同步JMB凭证
     */
    function _setBalance(address account, uint256 newBalance) internal {
        // 先结算已有分红
        _updateReward(account);

        uint256 oldBalance = shares[account];
        if (oldBalance == newBalance) return;

        // 更新份额
        if (newBalance > oldBalance) {
            uint256 increase = newBalance - oldBalance;
            totalShares += increase;
            shares[account] = newBalance;
            emit Transfer(address(0), account, increase);
        } else {
            uint256 decrease = oldBalance - newBalance;
            totalShares -= decrease;
            shares[account] = newBalance;
            emit Transfer(account, address(0), decrease);

            // 份额减少到0时, 重置needBuyToUnlock为当前pendingReward
            // 防止反复进出门槛导致needBuyToUnlock不断累积
            if (newBalance == 0 && pendingReward[account] > 0) {
                needBuyToUnlock[account] = pendingReward[account];
                boughtAmount[account] = 0;
            }
        }

        // 重置debt, 避免新增份额获得历史分红
        userDebt[account] = accBNBPerShare;

        emit BalanceUpdated(account, oldBalance, newBalance);
    }

    /**
     * @dev 结算用户分红: 计算新增分红并累加到pendingReward
     */
    function _updateReward(address account) internal {
        uint256 userShares = shares[account];
        if (userShares == 0) {
            userDebt[account] = accBNBPerShare;
            return;
        }

        uint256 reward = (userShares * (accBNBPerShare - userDebt[account])) / 1e18;
        if (reward > 0) {
            pendingReward[account] += reward;
            // 需要购买同等金额才能解锁
            needBuyToUnlock[account] += reward;
        }

        userDebt[account] = accBNBPerShare;
    }

    /**
     * @dev 获取LP对应的BNB价值
     */
    function _getLPBNBValue(uint256 lpAmount) internal view returns (uint256) {
        IPancakePair pair = IPancakePair(lpPair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lpTotalSupply = pair.totalSupply();

        if (lpTotalSupply == 0) return 0;

        address token0 = pair.token0();
        uint256 bnbReserve = token0 == WBNB ? reserve0 : reserve1;

        // LP对应的BNB价值 (单边: 用户投入的BNB部分)
        return (lpAmount * bnbReserve) / lpTotalSupply;
    }

    // ========== 查询功能 ==========

    /**
     * @dev 查询用户状态
     */
    function getUserInfo(address user) external view returns (
        uint256 userShares,
        uint256 pending,
        uint256 unlocked,
        uint256 needBuy,
        uint256 bought
    ) {
        userShares = shares[user];

        // 计算当前待领取(含未结算增量)
        if (userShares > 0) {
            uint256 reward = (userShares * (accBNBPerShare - userDebt[user])) / 1e18;
            pending = pendingReward[user] + reward;
        } else {
            pending = pendingReward[user];
        }

        unlocked = unlockedReward[user];
        needBuy = needBuyToUnlock[user];
        bought = boughtAmount[user];
    }

    /**
     * @dev 返回用户当前待解锁分红(包含未结算增量)
     */
    function getPendingReward(address user) external view returns (uint256) {
        uint256 userShares = shares[user];
        if (userShares == 0) return pendingReward[user];
        uint256 reward = (userShares * (accBNBPerShare - userDebt[user])) / 1e18;
        return pendingReward[user] + reward;
    }

    /**
     * @dev 紧急提取BNB(仅owner)
     */
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }

    // ========== 内置JMB凭证(不可转让ERC20) ==========

    function totalSupply() external view override returns (uint256) {
        return totalShares;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return shares[account];
    }

    function allowance(
        address,
        address
    ) external pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        revert NonTransferable();
    }

    function transfer(address, uint256) external pure override returns (bool) {
        revert NonTransferable();
    }

    function transferFrom(
        address,
        address,
        uint256
    ) external pure override returns (bool) {
        revert NonTransferable();
    }
}
