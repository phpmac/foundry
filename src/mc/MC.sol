// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IPancakeRouter.sol";
import "./interfaces/IPancakeFactory.sol";
import "./interfaces/ITaxDistributor.sol";

/**
 * @title MC Token
 * @dev 带交易税收和白名单功能的ERC20代币
 */
contract MC is ERC20, Ownable {
    // ========== 状态变量 ==========

    // 交易开关: false=禁止交易, true=开放交易
    bool public tradingEnabled = false;

    // 销毁下限: 总量达到此值时停止销毁 (1200万)
    uint256 public constant BURN_THRESHOLD = 12_000_000;

    // 卖出税配置 (总计10%)
    uint256 public constant SELL_TAX = 1000; // 10% (基数为10000)
    uint256 public constant TAX_ADDR1 = 200; // 2% 钱包1
    uint256 public constant TAX_BURN = 300; // 3% 黑洞
    uint256 public constant TAX_ADDR2 = 300; // 3% 钱包2
    uint256 public constant TAX_ADDR3 = 200; // 2% 钱包3

    // 税收接收地址
    address public taxWallet1;
    address public taxWallet2;
    address public taxWallet3;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // 税收分发合约
    address public taxDistributor;

    // 白名单
    mapping(address => bool) public isWhitelisted;

    // 是否为交易对 (swap相关)
    mapping(address => bool) public isPair;

    // PancakeSwap Router (保留以便其他功能使用)
    address public pancakeRouter;

    // 税收分发开关: true=转发到分发合约, false=直接发给钱包
    bool public distributeTaxEnabled = true;

    // USDT地址 (BSC主网固定)
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    // 防止 swap 重入锁
    bool private _inSwap;

    // ========== 事件 ==========

    event TradingEnabled(bool enabled);
    event WhitelistUpdated(address indexed account, bool status);
    event PairCreated(address indexed pair, address indexed router);
    event PairUpdated(address indexed pair, bool status);
    event TaxWalletsUpdated(address wallet1, address wallet2, address wallet3);
    event TaxDistributorUpdated(address distributor);
    event BurnStop(uint256 deadBalance);

    // ========== 构造函数 ==========

    constructor(
        address _taxWallet1,
        address _taxWallet2,
        address _taxWallet3
    ) ERC20("MC", "MC") Ownable(msg.sender) {
        require(
            _taxWallet1 != address(0) &&
                _taxWallet2 != address(0) &&
                _taxWallet3 != address(0),
            "Invalid wallet"
        );

        taxWallet1 = _taxWallet1;
        taxWallet2 = _taxWallet2;
        taxWallet3 = _taxWallet3;

        // 铸造总量1.2亿给部署者
        _mint(msg.sender, 120_000_000 * 10 ** decimals());
    }

    // ========== 管理功能 ==========

    /**
     * @dev 开启/关闭交易
     */
    function setTradingEnabled(bool _enabled) external onlyOwner {
        tradingEnabled = _enabled;
        emit TradingEnabled(_enabled);
    }

    /**
     * @dev 设置白名单
     */
    function setWhitelist(address account, bool status) external onlyOwner {
        isWhitelisted[account] = status;
        emit WhitelistUpdated(account, status);
    }

    /**
     * @dev 批量设置白名单
     */
    function setWhitelistBatch(
        address[] calldata accounts,
        bool status
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = status;
            emit WhitelistUpdated(accounts[i], status);
        }
    }

    /**
     * @dev 设置交易对
     */
    function setPair(address pair, bool status) external onlyOwner {
        isPair[pair] = status;
        emit PairUpdated(pair, status);
    }

    /**
     * @dev 更新税收钱包
     */
    function setTaxWallets(
        address _wallet1,
        address _wallet2,
        address _wallet3
    ) external onlyOwner {
        require(
            _wallet1 != address(0) &&
                _wallet2 != address(0) &&
                _wallet3 != address(0),
            "Invalid wallet"
        );
        taxWallet1 = _wallet1;
        taxWallet2 = _wallet2;
        taxWallet3 = _wallet3;
        emit TaxWalletsUpdated(_wallet1, _wallet2, _wallet3);
    }

    /**
     * @dev 设置PancakeSwap Router
     */
    function setPancakeRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router");
        pancakeRouter = _router;
    }

    /**
     * @dev 创建交易对
     */
    function createPair(
        address _router
    ) external onlyOwner returns (address pair) {
        require(_router != address(0), "Invalid router");

        pancakeRouter = _router;

        // 创建 MC/USDT 交易对
        pair = IPancakeFactory(IPancakeRouter(_router).factory()).createPair(
            address(this),
            USDT
        );

        // 在 pair 赋值后更新状态
        isPair[pair] = true;

        emit PairCreated(pair, _router);
        emit PairUpdated(pair, true);
    }

    /**
     * @dev 设置税收分发开关
     * @notice 开启: 税收MC转发到分发合约
     * @notice 关闭: 税收MC直接发给钱包,由钱包自己换U
     */
    function setDistributeTaxEnabled(bool _enabled) external onlyOwner {
        distributeTaxEnabled = _enabled;
    }

    /**
     * @dev 设置税收分发合约
     */
    function setTaxDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "Invalid distributor");
        taxDistributor = _distributor;
        emit TaxDistributorUpdated(_distributor);
    }

    /**
     * @dev 更新税收钱包
     */
    function updateTaxWallets(
        address _wallet1,
        address _wallet2,
        address _wallet3
    ) external onlyOwner {
        require(
            _wallet1 != address(0) &&
                _wallet2 != address(0) &&
                _wallet3 != address(0),
            "Invalid wallet"
        );
        taxWallet1 = _wallet1;
        taxWallet2 = _wallet2;
        taxWallet3 = _wallet3;
        emit TaxWalletsUpdated(_wallet1, _wallet2, _wallet3);
    }

    // ========== 核心转账逻辑 ==========

    /**
     * @dev 检查黑洞地址是否已累积达到销毁阈值
     */
    function _checkBurnThreshold() internal view returns (bool) {
        return balanceOf(DEAD) >= BURN_THRESHOLD * 10 ** decimals();
    }

    /**
     * @dev 应用卖出税
     * 流程: 1.税收MC转发到分发合约 2.自动调用distributeTax() swap 3.3%进黑洞 4.返回实际转账金额
     */
    function _applySellTax(
        address from,
        address, // to - 保留参数以便扩展
        uint256 amount
    ) internal returns (uint256 actualAmount) {
        // 计算各钱包应得的MC数量
        uint256 mcForWallet1 = (amount * TAX_ADDR1) / 10000;
        uint256 mcForWallet2 = (amount * TAX_ADDR2) / 10000;
        uint256 mcForWallet3 = (amount * TAX_ADDR3) / 10000;
        uint256 burnAmount = (amount * TAX_BURN) / 10000;
        uint256 totalTaxMc = mcForWallet1 + mcForWallet2 + mcForWallet3;

        // 1. 将税收MC转发到分发合约或直接发给钱包
        if (totalTaxMc > 0) {
            if (distributeTaxEnabled && taxDistributor != address(0)) {
                // 转发到分发合约
                super._update(from, taxDistributor, totalTaxMc);

                // 2. 自动调用 distributeTax() 进行 swap 分发
                // 使用 try/catch 确保 swap 失败不影响用户转账
                if (!_inSwap) {
                    _inSwap = true;
                    try ITaxDistributor(taxDistributor).distributeTax() {} catch {}
                    _inSwap = false;
                }
            } else {
                // 直接发给钱包
                if (mcForWallet1 > 0) {
                    super._update(from, taxWallet1, mcForWallet1);
                }
                if (mcForWallet2 > 0) {
                    super._update(from, taxWallet2, mcForWallet2);
                }
                if (mcForWallet3 > 0) {
                    super._update(from, taxWallet3, mcForWallet3);
                }
            }
        }

        // 3. 黑洞销毁 (检查是否达到阈值)
        if (!_checkBurnThreshold()) {
            super._update(from, DEAD, burnAmount);
            // 未达到阈值，税率10%
            actualAmount = amount - (SELL_TAX * amount) / 10000;
        } else {
            // 已达到销毁下限，停止销毁，税率降为7%
            actualAmount = amount - ((SELL_TAX - TAX_BURN) * amount) / 10000;
            emit BurnStop(balanceOf(DEAD));
        }
    }

    /**
     * @dev 核心转账逻辑 - 应用交易规则
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // 检查交易开关
        if (!tradingEnabled) {
            // owner和合约本身总是可以交易
            // 白名单用户可以交易
            require(
                from == owner() ||
                    to == owner() ||
                    from == address(this) ||
                    to == address(this) ||
                    isWhitelisted[from] ||
                    isWhitelisted[to],
                "Trading not enabled"
            );
        }

        uint256 actualAmount = amount;

        // 只对卖出操作收税 (从交易对转出)
        // 排除: 发送者是合约本身(swap时)、白名单、owner、税收分发合约
        if (
            isPair[to] &&
            !isWhitelisted[from] &&
            from != owner() &&
            from != address(this) &&
            from != taxDistributor
        ) {
            actualAmount = _applySellTax(from, to, amount);
        }

        super._update(from, to, actualAmount);
    }

    // ========== 视图函数 ==========

    /**
     * @dev 查看当前是否已达到销毁阈值
     */
    function hasReachedBurnThreshold() external view returns (bool) {
        return _checkBurnThreshold();
    }
}
