// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPancakeRouter.sol";
import "./interfaces/IPancakeFactory.sol";
import "./interfaces/IPancakePair.sol";
import "./interfaces/ILPDistributor.sol";

/**
 * @title JM Token
 * @dev 带滑点、LP分红、私募、燃烧功能的ERC20代币
 */
contract JMToken is ERC20, Ownable {
    // ========== 常量 ==========

    // 发行总量: 2100万
    uint256 public constant TOTAL_SUPPLY = 21_000_000 ether;

    // 交易所锁仓: 200万(1年)
    uint256 public constant EXCHANGE_LOCK = 2_000_000 ether;

    // 燃烧总量: 500万(分10个月)
    uint256 public constant TOTAL_BURN_AMOUNT = 5_000_000 ether;
    uint256 public constant MONTHLY_BURN = 500_000 ether;
    uint256 public constant BURN_INTERVAL = 30 days;

    // 私募参数
    uint256 public constant PRIVATE_SALE_PRICE = 0.2 ether; // 0.2 BNB/份
    uint256 public constant PRIVATE_SALE_TOKENS = 6000 ether; // 6000 JM/份
    uint256 public constant PRIVATE_SALE_MAX = 2000; // 最大2000份

    // 死亡地址
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    // WBNB地址
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // 滑点基数
    uint256 public constant FEE_BASE = 10000;

    // 买滑点 3%: 1%回流, 1.5%LP分红, 0.5%黑洞
    uint256 public constant BUY_LIQUIDITY = 100; // 1%
    uint256 public constant BUY_LP_REWARD = 150; // 1.5%
    uint256 public constant BUY_BURN = 50; // 0.5%

    // 卖滑点 3%: 1%回流, 1.5%LP分红, 0.5%黑洞
    uint256 public constant SELL_LIQUIDITY = 100; // 1%
    uint256 public constant SELL_LP_REWARD = 150; // 1.5%
    uint256 public constant SELL_BURN = 50; // 0.5%

    // 撤池子税 20%: 10%回流, 5%LP分红, 5%黑洞
    uint256 public constant REMOVE_LIQUIDITY_FEE = 2000; // 20%
    uint256 public constant REMOVE_LIQUIDITY = 1000; // 10%
    uint256 public constant REMOVE_LP_REWARD = 500; // 5%
    uint256 public constant REMOVE_BURN = 500; // 5%

    // ========== 状态变量 ==========

    // PancakeSwap Router
    address public pancakeRouter;
    // LP Pair
    address public lpPair;
    // LP分红合约
    address public lpDistributor;

    // 交易开关
    bool public tradingEnabled = false;
    // 私募开关
    bool public privateSaleEnabled = true;

    // 燃烧状态
    uint256 public burnCount = 0;
    uint256 public lastBurnTime;

    // 私募状态
    uint256 public privateSaleSold = 0;
    // 私募收款地址 - 可修改
    address public privateSaleRecipient;

    // 交易所锁仓200万 - 1年解锁
    uint256 public constant EXCHANGE_LOCK_AMOUNT = 2_000_000 ether;
    uint256 public constant LOCK_PERIOD = 365 days;
    address public exchangeLockRecipient; // 解锁后接收地址
    uint256 public exchangeLockUnlockTime; // 解锁时间戳
    bool public exchangeLockClaimed = false; // 是否已解锁

    // 白名单
    mapping(address => bool) public isWhitelisted;
    // 黑名单
    mapping(address => bool) public isBlacklisted;

    // 防重入锁
    bool private _inSwap = false;

    // ========== 事件 ==========

    event TradingEnabled(bool enabled);
    event PrivateSaleEnabled(bool enabled);
    event WhitelistUpdated(address indexed account, bool status);
    event BlacklistUpdated(address indexed account, bool status);
    event MonthlyBurn(uint256 indexed month, uint256 amount);
    event PrivateSalePurchase(address indexed buyer, uint256 bnbAmount, uint256 tokenAmount);
    event LPRewardDistributed(uint256 amount);
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event ExchangeLockClaimed(address indexed recipient, uint256 amount, uint256 unlockTime);
    event PrivateSaleRecipientUpdated(address indexed newRecipient);

    // ========== 构造函数 ==========

    constructor(address _pancakeRouter) ERC20("JM Token", "JM") Ownable(msg.sender) {
        require(_pancakeRouter != address(0), "Invalid router");
        pancakeRouter = _pancakeRouter;

        // 铸造总量给部署者
        _mint(msg.sender, TOTAL_SUPPLY);

        // 创建交易对
        address pair = IPancakeFactory(IPancakeRouter(_pancakeRouter).factory())
            .createPair(address(this), WBNB);
        lpPair = pair;

        // 设置lastBurnTime为当前时间,首次燃烧需等待30天
        lastBurnTime = block.timestamp;

        // 设置私募收款地址 - 默认地址但可修改
        privateSaleRecipient = 0x23A3af0603918Ba5B0B5f6324DBFaa56d16856fF;

        // 设置交易所锁仓参数 - 固定解锁地址
        exchangeLockRecipient = 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e;
        exchangeLockUnlockTime = block.timestamp + LOCK_PERIOD;

        // 添加合约本身到白名单
        isWhitelisted[address(this)] = true;
        isWhitelisted[msg.sender] = true;
    }

    // ========== 修饰符 ==========

    modifier lockSwap() {
        require(!_inSwap, "Reentrancy");
        _inSwap = true;
        _;
        _inSwap = false;
    }

    // ========== 管理功能 ==========

    function setTradingEnabled(bool _enabled) external onlyOwner {
        tradingEnabled = _enabled;
        emit TradingEnabled(_enabled);
    }

    function setPrivateSaleEnabled(bool _enabled) external onlyOwner {
        privateSaleEnabled = _enabled;
        emit PrivateSaleEnabled(_enabled);
    }

    function setWhitelist(address account, bool status) external onlyOwner {
        isWhitelisted[account] = status;
        emit WhitelistUpdated(account, status);
    }

    function setBlacklist(address account, bool status) external onlyOwner {
        isBlacklisted[account] = status;
        emit BlacklistUpdated(account, status);
    }

    function setLPDistributor(address _distributor) external onlyOwner {
        lpDistributor = _distributor;
        isWhitelisted[_distributor] = true;
    }

    /**
     * @dev 修改私募收款地址 - 仅owner
     */
    function setPrivateSaleRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "Invalid recipient");
        privateSaleRecipient = _recipient;
        emit PrivateSaleRecipientUpdated(_recipient);
    }

    // ========== 接收BNB ==========

    receive() external payable {
        // 私募自动发放
        if (privateSaleEnabled && msg.value == PRIVATE_SALE_PRICE) {
            _processPrivateSale(msg.sender);
        }
    }

    // ========== 私募功能 ==========

    function _processPrivateSale(address buyer) internal {
        require(privateSaleSold < PRIVATE_SALE_MAX, "Private sale ended");
        require(balanceOf(address(this)) >= PRIVATE_SALE_TOKENS, "Insufficient tokens");

        privateSaleSold++;

        // 发送JM代币给买家
        _transfer(address(this), buyer, PRIVATE_SALE_TOKENS);

        // 将收到的BNB转给私募收款地址
        (bool success, ) = privateSaleRecipient.call{value: msg.value}("");
        require(success, "BNB transfer failed");

        emit PrivateSalePurchase(buyer, PRIVATE_SALE_PRICE, PRIVATE_SALE_TOKENS);
    }

    function buyPrivateSale() external payable {
        require(privateSaleEnabled, "Private sale closed");
        require(msg.value == PRIVATE_SALE_PRICE, "Send 0.2 BNB");
        _processPrivateSale(msg.sender);
    }

    // ========== 每月燃烧 ==========

    /**
     * @dev 每月燃烧 - 任何人可调用
     * 从底池(LP Pair)直接转JM到死亡地址销毁
     */
    function monthlyBurn() external {
        require(burnCount < 10, "Burn completed");
        require(block.timestamp >= lastBurnTime + BURN_INTERVAL, "Too early");

        uint256 burnAmount = MONTHLY_BURN;

        // 从底池直接转JM到死亡地址销毁
        // 使用super._update绕过pair的特殊处理
        super._update(lpPair, DEAD, burnAmount);

        burnCount++;
        lastBurnTime = block.timestamp;

        emit MonthlyBurn(burnCount, burnAmount);
    }

    // ========== 核心转账逻辑 ==========

    function _update(address from, address to, uint256 amount) internal override {
        // 黑名单检查
        require(!isBlacklisted[from] && !isBlacklisted[to], "Blacklisted");

        // 买入限制(排除燃烧到DEAD的情况)
        if (isBuy(from, to) && to != DEAD) {
            require(
                tradingEnabled || isWhitelisted[to] || to == owner(),
                "Trading not enabled"
            );
        }

        // 判断交易类型
        bool isSellTx = isSell(from, to);
        bool isBuyTx = isBuy(from, to);
        bool isRemoveLP = isRemoveLiquidity(from, to);

        if (isBuyTx) {
            // 买入: 应用买滑点,记录购买金额用于解锁LP分红
            _processBuy(from, to, amount);
        } else if (isSellTx) {
            // 卖出: 应用卖滑点
            _processSell(from, to, amount);
        } else if (isRemoveLP) {
            // 撤池子: 应用撤池子税
            _processRemoveLiquidity(from, to, amount);
        } else {
            // 普通转账
            super._update(from, to, amount);
        }
    }

    /**
     * @dev 判断是否为买入(从LP到用户)
     */
    function isBuy(address from, address to) public view returns (bool) {
        return from == lpPair && to != pancakeRouter && to != address(this);
    }

    /**
     * @dev 判断是否为卖出(从用户到LP)
     */
    function isSell(address from, address to) public view returns (bool) {
        return to == lpPair && from != pancakeRouter && from != address(this);
    }

    /**
     * @dev 判断是否为撤池子(从LP合约转出LP token)
     * 简化为: to是router且from不是pair和合约
     */
    function isRemoveLiquidity(address from, address to) public view returns (bool) {
        // 撤池子时: 用户调用Router.removeLiquidity,LP token会先转到Router
        // 这里简化为判断from是pair的情况
        return from == lpPair && to == pancakeRouter;
    }

    /**
     * @dev 处理买入
     */
    function _processBuy(address from, address to, uint256 amount) internal {
        // 计算滑点
        uint256 liquidityFee = (amount * BUY_LIQUIDITY) / FEE_BASE;
        uint256 rewardFee = (amount * BUY_LP_REWARD) / FEE_BASE;
        uint256 burnFee = (amount * BUY_BURN) / FEE_BASE;
        uint256 totalFee = liquidityFee + rewardFee + burnFee;

        // 实际到账
        uint256 receiveAmount = amount - totalFee;

        // 执行转账
        super._update(from, to, receiveAmount);

        // 处理费用
        if (liquidityFee > 0) {
            super._update(from, address(this), liquidityFee);
        }
        if (burnFee > 0) {
            super._update(from, DEAD, burnFee);
        }
        if (rewardFee > 0) {
            super._update(from, address(this), rewardFee);
            _distributeLPReward(rewardFee);
        }

        // 记录购买金额(用于解锁LP分红)
        if (lpDistributor != address(0)) {
            // 计算用户花了多少BNB(近似值)
            uint256 bnbSpent = _getBNBAmountForTokens(amount);
            ILPDistributor(lpDistributor).recordBuy(to, bnbSpent);
        }
    }

    /**
     * @dev 处理卖出
     */
    function _processSell(address from, address to, uint256 amount) internal {
        // 计算滑点
        uint256 liquidityFee = (amount * SELL_LIQUIDITY) / FEE_BASE;
        uint256 rewardFee = (amount * SELL_LP_REWARD) / FEE_BASE;
        uint256 burnFee = (amount * SELL_BURN) / FEE_BASE;
        uint256 totalFee = liquidityFee + rewardFee + burnFee;

        // 实际到账LP的代币
        uint256 lpReceiveAmount = amount - totalFee;

        // 先转费用到合约
        if (liquidityFee > 0) {
            super._update(from, address(this), liquidityFee);
        }
        if (burnFee > 0) {
            super._update(from, DEAD, burnFee);
        }
        if (rewardFee > 0) {
            super._update(from, address(this), rewardFee);
            _distributeLPReward(rewardFee);
        }

        // 剩余转给LP
        super._update(from, to, lpReceiveAmount);
    }

    /**
     * @dev 处理撤池子
     */
    function _processRemoveLiquidity(address from, address to, uint256 amount) internal {
        // 撤池子税20%
        uint256 fee = (amount * REMOVE_LIQUIDITY_FEE) / FEE_BASE;
        uint256 liquidityFee = (amount * REMOVE_LIQUIDITY) / FEE_BASE;
        uint256 rewardFee = (amount * REMOVE_LP_REWARD) / FEE_BASE;
        uint256 burnFee = (amount * REMOVE_BURN) / FEE_BASE;

        // 实际到账
        uint256 receiveAmount = amount - fee;

        // 执行转账
        super._update(from, to, receiveAmount);

        // 处理税费
        if (liquidityFee > 0) {
            super._update(from, address(this), liquidityFee);
        }
        if (burnFee > 0) {
            super._update(from, DEAD, burnFee);
        }
        if (rewardFee > 0) {
            super._update(from, address(this), rewardFee);
            _distributeLPReward(rewardFee);
        }
    }

    /**
     * @dev 分发LP分红
     */
    function _distributeLPReward(uint256 tokenAmount) internal lockSwap {
        if (lpDistributor == address(0)) return;

        // swap代币为BNB并发送到分红合约
        _swapTokensForBNB(tokenAmount);

        uint256 bnbBalance = address(this).balance;
        if (bnbBalance > 0) {
            (bool success, ) = lpDistributor.call{value: bnbBalance}("");
            if (success) {
                emit LPRewardDistributed(bnbBalance);
            }
        }
    }

    /**
     * @dev 将代币swap为BNB
     */
    function _swapTokensForBNB(uint256 tokenAmount) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;

        _approve(address(this), pancakeRouter, tokenAmount);

        IPancakeRouter(pancakeRouter).swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev 根据代币数量估算BNB金额
     */
    function _getBNBAmountForTokens(uint256 tokenAmount) internal view returns (uint256) {
        IPancakePair pair = IPancakePair(lpPair);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        address token0 = pair.token0();
        if (token0 == WBNB) {
            // reserve0是BNB, reserve1是JM
            if (reserve1 == 0) return 0;
            return (tokenAmount * uint256(reserve0)) / uint256(reserve1);
        } else {
            // reserve0是JM, reserve1是BNB
            if (reserve0 == 0) return 0;
            return (tokenAmount * uint256(reserve1)) / uint256(reserve0);
        }
    }

    // ========== 交易所锁仓解锁 ==========

    /**
     * @dev 解锁交易所锁仓的200万枚 - 任何人可在时间到了后调用
     */
    function claimExchangeLock() external {
        require(!exchangeLockClaimed, "Already claimed");
        require(block.timestamp >= exchangeLockUnlockTime, "Lock period not ended");
        require(balanceOf(address(this)) >= EXCHANGE_LOCK_AMOUNT, "Insufficient balance");

        exchangeLockClaimed = true;
        _transfer(address(this), exchangeLockRecipient, EXCHANGE_LOCK_AMOUNT);

        emit ExchangeLockClaimed(exchangeLockRecipient, EXCHANGE_LOCK_AMOUNT, block.timestamp);
    }

    /**
     * @dev 查看锁仓状态
     */
    function getExchangeLockStatus() external view returns (
        uint256 amount,
        uint256 unlockTime,
        bool canClaim,
        bool claimed,
        address recipient
    ) {
        amount = EXCHANGE_LOCK_AMOUNT;
        unlockTime = exchangeLockUnlockTime;
        canClaim = !exchangeLockClaimed && block.timestamp >= exchangeLockUnlockTime;
        claimed = exchangeLockClaimed;
        recipient = exchangeLockRecipient;
    }

    // ========== 流动性管理 ==========

    /**
     * @dev 添加流动性(仅owner)
     */
    function addLiquidity(uint256 tokenAmount) external payable onlyOwner {
        require(tokenAmount > 0 && msg.value > 0, "Invalid amount");

        _approve(address(this), pancakeRouter, tokenAmount);

        IPancakeRouter(pancakeRouter).addLiquidityETH{value: msg.value}(
            address(this),
            tokenAmount,
            0,
            0,
            address(this), // LP token发给合约,用于燃烧
            block.timestamp
        );

        emit LiquidityAdded(tokenAmount, msg.value);
    }

    /**
     * @dev 提取合约中的代币(仅owner,紧急情况)
     */
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }

    /**
     * @dev 提取合约中的BNB(仅owner,紧急情况)
     */
    function withdrawBNB(uint256 amount) external onlyOwner {
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Transfer failed");
    }

    // ========== 视图函数 ==========

    function getBurnStatus() external view returns (uint256 _burnCount, uint256 _nextBurnTime, bool _canBurn) {
        _burnCount = burnCount;
        _nextBurnTime = lastBurnTime + BURN_INTERVAL;
        _canBurn = burnCount < 10 && block.timestamp >= _nextBurnTime;
    }

    function getPrivateSaleStatus() external view returns (uint256 sold, uint256 remaining, bool enabled) {
        sold = privateSaleSold;
        remaining = PRIVATE_SALE_MAX - privateSaleSold;
        enabled = privateSaleEnabled;
    }
}

