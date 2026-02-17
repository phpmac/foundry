// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPancakeRouter.sol";
import "./interfaces/IPancakeFactory.sol";
import "./interfaces/IPancakePair.sol";
import "./interfaces/ILPDistributor.sol";
import "./interfaces/IWBNB.sol";

/**
 * @title JM Token
 * @dev 带滑点、LP分红、私募、燃烧功能的ERC20代币
 */
contract JMToken is ERC20, Ownable {
    // ========== 常量 ==========

    // 发行总量: 2100万
    uint256 public constant TOTAL_SUPPLY = 21_000_000 ether;
    uint256 public constant RESERVED_SUPPLY = 19_000_000 ether; // 私募1200万 + 燃烧500万 + 锁仓200万

    // 固定销毁: 500万
    uint256 public constant BURN_AMOUNT = 5_000_000 ether;

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

    // 私募状态
    uint256 public privateSaleSold = 0;
    mapping(address => bool) public privateSaleParticipated; // 每个地址仅可参与一次
    // TODO 私募收款地址
    address public constant PRIVATE_SALE_RECIPIENT =
        0x23A3af0603918Ba5B0B5f6324DBFaa56d16856fF;

    // 交易所锁仓200万 - 1年解锁
    uint256 public constant EXCHANGE_LOCK_AMOUNT = 2_000_000 ether;
    uint256 public constant LOCK_PERIOD = 365 days;
    // TODO 交易所锁仓接收地址
    address public constant EXCHANGE_LOCK_RECIPIENT =
        0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e; // 解锁后接收地址
    uint256 public exchangeLockUnlockTime; // 解锁时间戳
    bool public exchangeLockClaimed = false; // 是否已解锁

    // 白名单
    mapping(address => bool) public isWhitelisted;
    // 黑名单
    mapping(address => bool) public isBlacklisted;

    // 防重入锁
    bool private _inSwap = false;
    bool public removeLiquidityTaxEnabled = true; // 默认开启,撤池子收20%手续费
    // 记录上次检测的 LP totalSupply,用于判断撤池
    uint256 private _lastLPTotalSupply;

    // LP分红累积: 先攒rewardFee, 等当前swap完成后再统一swap分发, 避免嵌套swap
    uint256 public pendingRewardTokens;
    uint256 public constant MIN_REWARD_SWAP = 100 ether; // 累积超过100 JM才触发swap分发

    // ========== 事件 ==========

    event TradingEnabled(bool enabled);
    event PrivateSaleEnabled(bool enabled);
    event WhitelistUpdated(address indexed account, bool status);
    event BlacklistUpdated(address indexed account, bool status);
    event PrivateSalePurchase(
        address indexed buyer,
        uint256 bnbAmount,
        uint256 tokenAmount
    );
    event LPRewardDistributed(uint256 amount);
    event LiquidityAdded(uint256 tokenAmount, uint256 bnbAmount);
    event ExchangeLockClaimed(
        address indexed recipient,
        uint256 amount,
        uint256 unlockTime
    );
    event PrivateSaleRecipientUpdated(address indexed newRecipient);

    // ========== 构造函数 ==========

    constructor(
        address _pancakeRouter
    ) ERC20("JM Token", "JM") Ownable(msg.sender) {
        require(_pancakeRouter != address(0), "Invalid router");
        pancakeRouter = _pancakeRouter;

        // 预留1900万到合约: 私募1200万 + 燃烧500万 + 锁仓200万
        _mint(address(this), RESERVED_SUPPLY);
        // 固定销毁500万到黑洞地址
        _burn(address(this), BURN_AMOUNT);

        // 剩余200万给部署者,用于运营与灵活配置
        _mint(msg.sender, TOTAL_SUPPLY - RESERVED_SUPPLY);

        // 创建交易对
        address pair = IPancakeFactory(IPancakeRouter(_pancakeRouter).factory())
            .createPair(address(this), WBNB);
        lpPair = pair;

        exchangeLockUnlockTime = block.timestamp + LOCK_PERIOD;

        // 初始化 LP totalSupply 记录
        if (lpPair != address(0)) {
            _lastLPTotalSupply = IPancakePair(lpPair).totalSupply();
        }

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

        // 初始化 LP totalSupply 记录
        if (lpPair != address(0)) {
            _lastLPTotalSupply = IPancakePair(lpPair).totalSupply();
        }

        // 排除关键地址参与LP分红
        if (_distributor != address(0)) {
            ILPDistributor(_distributor).excludeFromDividends(lpPair);
            ILPDistributor(_distributor).excludeFromDividends(pancakeRouter);
            ILPDistributor(_distributor).excludeFromDividends(DEAD);
            ILPDistributor(_distributor).excludeFromDividends(address(this));
            ILPDistributor(_distributor).excludeFromDividends(_distributor);
            ILPDistributor(_distributor).excludeFromDividends(address(0));
        }
    }

    function setRemoveLiquidityTaxEnabled(bool enabled) external onlyOwner {
        removeLiquidityTaxEnabled = enabled;
    }

    // ========== 接收BNB ==========

    receive() external payable {
        // 私募自动发放
        if (privateSaleEnabled) {
            if (msg.value == PRIVATE_SALE_PRICE) {
                _processPrivateSale(msg.sender);
            } else {
                // 否则就报错,免退回
                revert("Invalid BNB amount");
            }
        } else {
            // 乱打钱就贡献给私募收款地址
            (bool success, ) = PRIVATE_SALE_RECIPIENT.call{value: msg.value}(
                ""
            );
            require(success, "BNB transfer failed");
        }
    }

    // ========== 私募功能 ==========

    function _processPrivateSale(address buyer) internal {
        require(privateSaleSold < PRIVATE_SALE_MAX, "Private sale ended");
        require(!privateSaleParticipated[buyer], "Already participated");
        require(
            balanceOf(address(this)) >= PRIVATE_SALE_TOKENS,
            "Insufficient tokens"
        );

        privateSaleSold++;
        privateSaleParticipated[buyer] = true;

        // 发送JM代币给买家
        _transfer(address(this), buyer, PRIVATE_SALE_TOKENS);

        // 将收到的BNB转给私募收款地址
        (bool success, ) = PRIVATE_SALE_RECIPIENT.call{value: msg.value}("");
        require(success, "BNB transfer failed");

        emit PrivateSalePurchase(
            buyer,
            PRIVATE_SALE_PRICE,
            PRIVATE_SALE_TOKENS
        );
    }

    // ========== 核心转账逻辑 ==========

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // mint/burn 不收税, 避免初始化阶段把mint误判为买入.
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        // 累积分红触发: 非swap状态 + 累积超过阈值时, 统一swap分发
        // 排除from/to为lpPair的情况, 因为pair.swap()回调内不能嵌套swap(Pancake: LOCKED)
        if (
            !_inSwap &&
            pendingRewardTokens >= MIN_REWARD_SWAP &&
            from != lpPair &&
            to != lpPair
        ) {
            _distributeLPReward(pendingRewardTokens);
            pendingRewardTokens = 0;
        }

        // 黑名单检查
        require(!isBlacklisted[from] && !isBlacklisted[to], "Blacklisted");

        bool hasLiquidity = _hasEffectiveLiquidity(); // 无有效流动性时全部按普通转账处理.

        // 买入限制(排除燃烧到DEAD的情况)
        if (hasLiquidity && isBuy(from, to) && to != DEAD) {
            require(
                tradingEnabled || isWhitelisted[to] || to == owner(),
                "Trading not enabled"
            );
        }

        // 关键: 撤池检测需要用 totalSupply 变化来判断
        // 撤池检测: pair 转出代币时(from=pair),检查 totalSupply 是否减少
        // removeLiquidity 调用 pair.burn() 会销毁 LP token,导致 totalSupply 减少
        // swap 不会改变 totalSupply
        bool isRemoveLP = false;
        if (hasLiquidity && from == lpPair && to != lpPair && to != address(this)) {
            uint256 currentSupply = IPancakePair(lpPair).totalSupply();
            // 如果 totalSupply 减少了,说明是 removeLiquidity(撤池)
            // 如果 totalSupply 不变,说明是 swap(买入)
            isRemoveLP = removeLiquidityTaxEnabled && currentSupply < _lastLPTotalSupply;
            // 无论是否撤池,都要更新记录(保持最新状态)
            _lastLPTotalSupply = currentSupply;
        }

        bool isSellTx = hasLiquidity && isSell(from, to); // 仅有流动性时识别卖出.
        bool isBuyTx = hasLiquidity && isBuy(from, to); // 仅有流动性时识别买入.

        // 撤池与买入互斥: 如果检测到撤池,则不走买入逻辑
        if (isRemoveLP) {
            isBuyTx = false;
        }

        if (isBuyTx && isWhitelisted[to]) {
            // 白名单买入免手续费, 但仍计入买入金额用于分红解锁
            super._update(from, to, amount);
            if (lpDistributor != address(0)) {
                uint256 bnbSpent = _getBNBAmountForTokens(amount);
                ILPDistributor(lpDistributor).recordBuy(to, bnbSpent);
            }
        } else if (isBuyTx) {
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

        // 同步from/to的LP余额到分红合约(自动追踪LP持有者)
        // 用try/catch防止分红合约异常阻断主交易
        if (lpDistributor != address(0) && !_inSwap) {
            try
                ILPDistributor(lpDistributor).setBalance(
                    from,
                    IPancakePair(lpPair).balanceOf(from)
                )
            {} catch {}
            try
                ILPDistributor(lpDistributor).setBalance(
                    to,
                    IPancakePair(lpPair).balanceOf(to)
                )
            {} catch {}
        }
    }

    /**
     * @dev 判断当前是否存在“有效流动性”.
     * 条件: lpPair已设置,且池子两边储备都大于0.
     * 目的: 在无流动性或pair异常时关闭手续费路径,避免误收税.
     */
    function _hasEffectiveLiquidity() internal view returns (bool) {
        if (lpPair == address(0)) return false; // pair未初始化.
        try IPancakePair(lpPair).getReserves() returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32
        ) {
            return reserve0 > 0 && reserve1 > 0; // 两边储备都>0才认为有有效流动性.
        } catch {
            return false; // pair异常时按无流动性处理, 避免误收税.
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
     * @dev 判断是否为撤池子(通过 totalSupply 变化检测)
     * 注意: 此函数需要在 _update 中结合 _lastLPTotalSupply 比较才能正确判断
     * 单独调用时只能返回基于静态条件的初步判断
     */
    function isRemoveLiquidity(
        address from,
        address to
    ) public view returns (bool) {
        if (!removeLiquidityTaxEnabled) return false;
        // pair 转出代币给用户 (from=pair, to=user) - 需要结合 totalSupply 变化判断
        // 撤池: from == lpPair, to != lpPair, totalSupply 减少
        // 买入: from == lpPair, to != lpPair, totalSupply 不变
        return from == lpPair && to != lpPair && to != pancakeRouter && to != address(this);
    }

    /**
     * @dev 获取 pair 当前 totalSupply(用于外部检测)
     */
    function getLPTotalSupply() external view returns (uint256) {
        return IPancakePair(lpPair).totalSupply();
    }

    /**
     * @dev 获取上次记录的 LP totalSupply(用于调试)
     */
    function getLastLPTotalSupply() external view returns (uint256) {
        return _lastLPTotalSupply;
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
        // buy路径下1%回流到底池: from本身就是lpPair, 不再转出即可留在池内
        if (burnFee > 0) {
            super._update(from, DEAD, burnFee);
        }
        if (rewardFee > 0) {
            // 累积到合约, 不在swap回调内立即swap, 避免嵌套swap导致pair K值校验失败
            super._update(from, address(this), rewardFee);
            pendingRewardTokens += rewardFee;
        }

        // 记录购买金额(用于解锁LP分红)
        if (lpDistributor != address(0)) {
            uint256 bnbSpent = _getBNBAmountForTokens(amount);
            ILPDistributor(lpDistributor).recordBuy(to, bnbSpent);
        }
    }

    /**
     * @dev 处理卖出
     */
    function _processSell(address from, address to, uint256 amount) internal {
        // 计算滑点
        uint256 rewardFee = (amount * SELL_LP_REWARD) / FEE_BASE;
        uint256 burnFee = (amount * SELL_BURN) / FEE_BASE;

        // 卖出1%回流到底池: 让lpReceive包含liquidityFee
        uint256 lpReceiveAmount = amount - rewardFee - burnFee;

        // 先转费用
        if (burnFee > 0) {
            super._update(from, DEAD, burnFee);
        }
        if (rewardFee > 0) {
            // 累积到合约, 不在swap回调内立即swap
            super._update(from, address(this), rewardFee);
            pendingRewardTokens += rewardFee;
        }

        // 剩余转给LP (含1%回流)
        super._update(from, to, lpReceiveAmount);
    }

    /**
     * @dev 处理撤池子
     */
    function _processRemoveLiquidity(
        address from,
        address to,
        uint256 amount
    ) internal {
        // 撤池子税20%
        uint256 fee = (amount * REMOVE_LIQUIDITY_FEE) / FEE_BASE;
        uint256 rewardFee = (amount * REMOVE_LP_REWARD) / FEE_BASE;
        uint256 burnFee = (amount * REMOVE_BURN) / FEE_BASE;

        // 实际到账
        uint256 receiveAmount = amount - fee;

        // 执行转账
        super._update(from, to, receiveAmount);

        // 处理税费
        // 撤池按需求10%回流到底池: 不再把liquidityFee转出, 直接留在lpPair
        if (burnFee > 0) {
            super._update(from, DEAD, burnFee);
        }
        if (rewardFee > 0) {
            // 累积到合约, 不在swap回调内立即swap
            super._update(from, address(this), rewardFee);
            pendingRewardTokens += rewardFee;
        }
    }

    /**
     * @dev 分发LP分红: 将累积的JM swap成WBNB, 直接发送到lpDistributor, 再通知其转换为BNB记账.
     * swap的to不能是address(this)(JMToken), 因为PancakeSwap禁止swap到pair中的token地址.
     * 所以直接swap到lpDistributor, 减少一次transfer.
     */
    function _distributeLPReward(uint256 tokenAmount) internal lockSwap {
        if (lpDistributor == address(0)) return;

        // swap JM -> WBNB, 直接发送到lpDistributor
        uint256 beforeWbnb = IWBNB(WBNB).balanceOf(lpDistributor);
        _swapTokensForWBNB(tokenAmount, lpDistributor);
        uint256 rewardWbnb = IWBNB(WBNB).balanceOf(lpDistributor) - beforeWbnb;

        if (rewardWbnb > 0) {
            ILPDistributor(lpDistributor).notifyRewardInWBNB(rewardWbnb);
            emit LPRewardDistributed(rewardWbnb);
        }
    }

    /**
     * @dev 将代币swap为WBNB, 发送到指定接收地址
     */
    function _swapTokensForWBNB(uint256 tokenAmount, address to) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;

        _approve(address(this), pancakeRouter, tokenAmount);

        IPancakeRouter(pancakeRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                to,
                block.timestamp
            );
    }

    /**
     * @dev 根据代币数量估算BNB金额
     */
    function _getBNBAmountForTokens(
        uint256 tokenAmount
    ) internal view returns (uint256) {
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
        require(
            block.timestamp >= exchangeLockUnlockTime,
            "Lock period not ended"
        );
        require(
            balanceOf(address(this)) >= EXCHANGE_LOCK_AMOUNT,
            "Insufficient balance"
        );

        exchangeLockClaimed = true;
        _transfer(address(this), EXCHANGE_LOCK_RECIPIENT, EXCHANGE_LOCK_AMOUNT);

        emit ExchangeLockClaimed(
            EXCHANGE_LOCK_RECIPIENT,
            EXCHANGE_LOCK_AMOUNT,
            block.timestamp
        );
    }

    /**
     * @dev 查看锁仓状态
     */
    function getExchangeLockStatus()
        external
        view
        returns (
            uint256 amount,
            uint256 unlockTime,
            bool canClaim,
            bool claimed,
            address recipient
        )
    {
        amount = EXCHANGE_LOCK_AMOUNT;
        unlockTime = exchangeLockUnlockTime;
        canClaim =
            !exchangeLockClaimed &&
            block.timestamp >= exchangeLockUnlockTime;
        claimed = exchangeLockClaimed;
        recipient = EXCHANGE_LOCK_RECIPIENT;
    }

    // ========== 流动性管理 ==========

    /**
     * @dev 添加流动性(仅owner)
     */
    // 添加流动性 (单币ETH)
    function addLiquidity(uint256 tokenAmount) external payable onlyOwner {
        require(tokenAmount > 0 && msg.value > 0, "Invalid amount");

        _transfer(msg.sender, address(this), tokenAmount);
        _approve(address(this), pancakeRouter, tokenAmount);

        IPancakeRouter(pancakeRouter).addLiquidityETH{value: msg.value}(
            address(this),
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp
        );

        // 更新 LP totalSupply 记录
        _lastLPTotalSupply = IPancakePair(lpPair).totalSupply();

        emit LiquidityAdded(tokenAmount, msg.value);
    }

    /**
     * @dev 手动同步 LP totalSupply 记录
     * 适用于通过 router 添加流动性后手动更新状态
     */
    function syncLPTotalSupply() external {
        _lastLPTotalSupply = IPancakePair(lpPair).totalSupply();
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

    function getPrivateSaleStatus()
        external
        view
        returns (uint256 sold, uint256 remaining, bool enabled)
    {
        sold = privateSaleSold;
        remaining = PRIVATE_SALE_MAX - privateSaleSold;
        enabled = privateSaleEnabled;
    }
}
