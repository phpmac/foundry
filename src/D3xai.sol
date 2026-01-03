// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPancakePair} from "./interface/IPancakePair.sol";
import {IPancakeRouter02} from "./interface/IPancakeRouter02.sol";
import {IPancakeFactory} from "./interface/IPancakeFactory.sol";
import {IMarking} from "./interface/IMarking.sol";

/**
 * D3XAI代币
 * 0.25U/枚
 * 总量4.5亿
 *
 * 5kw 预留在空投合约 contracts/token/Airdrop.sol
 *
 */
contract D3xai is ERC20Upgradeable, AccessControlUpgradeable {
    bytes32 public constant SELL_ROLE = keccak256("SELL_ROLE"); // 用于卖出

    // 允许的测试网ID
    uint256[] public allowTestChainId;

    uint256 public constant TOTAL_SUPPLY = 450000000 ether; // 总量4.5亿

    uint256 public transferDailyLimit; // 每地址24小时转出限额,以最小单位计,0表示不限制
    mapping(address => uint256) public transferDailyAmount; // 当前窗口内已转出
    mapping(address => uint256) public transferDailyWindowStart; // 窗口开始时间

    uint256 public dailyTradeVolume; // 当天交易量
    uint256 public dailyTradeLimit; // 日交易限额
    mapping(address => bool) public whitelist; // 白名单地址

    IPancakePair public pair; // 交易对地址

    mapping(address => uint256) public lastBuy; // 买入时间

    IPancakeRouter02 public pancakeRouter; // PancakeSwap Router
    IERC20 public usdt; // USDT地址

    uint256 public highestPrice; // 记录最高价

    bool private _inBurn; // @deprecated 防止重入标志,防止多次销毁
    uint256 private _pendingBurn; // @deprecated 待销毁数量
    address private _pendingBurnPair; // @deprecated 待销毁的交易对
    address private _pendingOrigin; // @deprecated 发起人

    uint256 public dailyOpenPrice; // 当日开盘价
    uint256 public dailyPriceWindowStart; // @deprecated 似乎没有用 当日价格窗口开始时间
    IMarking public markingContract; // Marking合约地址
    bool private _inMarketControl; // 正在执行市场控制标志,防止重入

    bool private inSwap;

    address public withdrawAddress; // 提现合约地址

    address public liquidityContract; // 流动性添加和移除中间合约地址

    address public pancakeBuyer; // PancakeSwap 购买并锁仓合约地址

    address public fiveFeeAddress; // 5%手续费地址,后面改成了2.5%

    uint256 public marketControlPrice; // 行情控制基准价格

    address public birdBuy; // 蜂鸟项目购买合约

    address public synthesisBuy; // 合成NFT购买合约地址

    address public buyContract; // 购买合约地址

    address public tokenSellContract; // 代币卖出合约地址

    // ! LP捐赠事件,手续费卖出到提现地址事件
    event WithdrawFee(
        address indexed withdrawAddress, // 提现地址
        uint256 sellD3xaiAmount, // 卖出D3XAI数量
        uint256 getUsdtAmount // 获得USDT数量
    );

    // 管理员铸造代币事件
    event MintD3xai(address indexed to, uint256 amount);

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    // 是否在允许的测试网
    modifier onlyTestChain() {
        require(isAllowTestChainId(), "Not testnet");
        _;
    }

    // ! 买入后限制转出和卖出,需要在2处做限制
    modifier buyCoolDown(address user) {
        if (lastBuy[user] > 0) {
            require(
                lastBuy[user] + 10 seconds < block.timestamp,
                "last buy time"
            );
        }

        _;
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _amount
    ) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        __ERC20_init(_name, _symbol);

        _mint(_msgSender(), _amount * 10 ** 18);

        addAllTestChain();
    }

    /**
     * 销毁底池代币
     * @param amount 销毁数量
     */
    function recycle(uint256 amount) external onlyRole(SELL_ROLE) {
        address uniswapV2Pair = address(pair);
        require(uniswapV2Pair != address(0), "pair not set");
        uint256 maxBurn = balanceOf(uniswapV2Pair) / 3;
        uint256 burn_maount = amount >= maxBurn ? maxBurn : amount;
        inSwap = true;
        super._burn(uniswapV2Pair, burn_maount);
        inSwap = false;
        pair.sync();
    }

    /**
     * 销毁指定用户代币(需要 SELL_ROLE)
     * @param user 用户地址
     * @param amount 销毁数量
     */
    function burnFrom(
        address user,
        uint256 amount
    ) external onlyRole(SELL_ROLE) {
        _burn(user, amount);
    }

    /**
     * 管理员批量添加测试网ID
     * @param _chainIds 链ID数组
     */
    function addTestChain(
        uint256[] memory _chainIds
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _chainIds.length; i++) {
            allowTestChainId.push(_chainIds[i]);
        }
    }

    /**
     * 管理员批量铸造
     * @param _to 铸造地址
     * @param _amount 铸造数量
     */
    function batchMint(
        address[] memory _to,
        uint256[] memory _amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _to.length; i++) {
            _mint(_to[i], _amount[i]);
            emit MintD3xai(_to[i], _amount[i]);
        }
    }

    /**
     * 创建USDT交易对
     */
    function createPair() public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(usdt) != address(0), "USDT address not set");
        require(address(pancakeRouter) != address(0), "router not set");
        require(address(pair) == address(0), "pair already set");

        address factory = pancakeRouter.factory();
        require(factory != address(0), "router factory not set");

        address created = IPancakeFactory(factory).getPair(
            address(this),
            address(usdt)
        );
        if (created == address(0)) {
            created = IPancakeFactory(factory).createPair(
                address(this),
                address(usdt)
            );
        }
        pair = IPancakePair(created);
    }

    /**
     * 管理员批量销毁
     * @param _to 销毁地址
     * @param _amount 销毁数量
     */
    function batchBurn(
        address[] memory _to,
        uint256[] memory _amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _to.length; i++) {
            _burn(_to[i], _amount[i]);
        }
    }

    /**
     * 仅测试网免费铸造代币
     * @param _amount 铸造数量
     */
    function freeMint(uint256 _amount) public onlyTestChain {
        _mint(_msgSender(), _amount);
    }

    /**
     * 是否在允许的测试网
     * @return 是否在允许的测试网
     */
    function isAllowTestChainId() public view returns (bool) {
        for (uint256 i = 0; i < allowTestChainId.length; i++) {
            if (allowTestChainId[i] == block.chainid) {
                return true;
            }
        }
        return false;
    }

    /**
     * 管理员添加所有测试网ID
     */
    function addAllTestChain() public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 97;
        addTestChain(chainIds);
    }

    /**
     * 管理员设置日交易限额
     * @param _dailyTradeLimit 日交易限额
     */
    function setDailyTradeLimit(
        uint256 _dailyTradeLimit
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        dailyTradeLimit = _dailyTradeLimit;
    }

    /**
     * 管理员设置每地址每日限额
     * @param _transferDailyLimit 每地址每日限额
     */
    function setTransferDailyLimit(
        uint256 _transferDailyLimit
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        transferDailyLimit = _transferDailyLimit;
    }

    /**
     * 获取代币价格
     * @return 价格
     */
    function price() public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(usdt);

        try pancakeRouter.getAmountsOut(1 ether, path) returns (
            uint256[] memory amounts
        ) {
            return amounts[1];
        } catch {
            revert("price error");
        }
    }

    /**
     * 平方根函数(Babylonian方法)
     * @param x 输入值
     * @return y 平方根
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /**
     * 行情控制参数,需要处以10000
     * @return 上涨超过10%,卖出5%,下跌超过10%,买入5%
     */
    function marketControlParams()
        public
        pure
        returns (uint256, uint256, uint256, uint256)
    {
        return (1000, 500, 1000, 500);
    }

    /**
     * 管理员设置Marking合约地址
     * @param _markingContract Marking合约地址
     */
    function setMarkingContract(
        address _markingContract
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_markingContract != address(0), "Invalid address");
        markingContract = IMarking(_markingContract);
        whitelist[_markingContract] = true; // 自动加入白名单
    }

    /**
     * 管理员设置行情控制基准价格
     * @param _marketControlPrice 行情控制基准价格
     */
    function setMarketControlPrice(
        uint256 _marketControlPrice
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_marketControlPrice > 0, "invalid price");
        marketControlPrice = _marketControlPrice;
    }

    /**
     * 内部价格控制逻辑
     * 通过买卖控制价格为基准价格,容差范围为 ±2%
     * 当价格超过基准价格 +2% 时卖出,低于基准价格 -2% 时买入
     */
    function executeMarketControl() internal lockTheSwap {
        if (address(markingContract) == address(0)) {
            return;
        }

        if (marketControlPrice == 0) {
            return;
        }

        uint256 currentPrice = price();
        uint256 tolerance = (marketControlPrice * 200) / 10000; // 2%忽略
        uint256 upperThreshold = marketControlPrice + tolerance;
        if (currentPrice > upperThreshold) {
            uint256 sellAmount = calculateSellAmount();
            if (
                sellAmount > 0 &&
                balanceOf(address(markingContract)) >= sellAmount
            ) {
                markingContract.sell(sellAmount);
            }
            return;
        }

        uint256 lowerThreshold = marketControlPrice > tolerance
            ? marketControlPrice - tolerance
            : marketControlPrice;
        if (currentPrice < lowerThreshold) {
            uint256 buyAmount = calculateBuyAmount();
            uint256 usdtBalance = usdt.balanceOf(address(markingContract));
            if (buyAmount > 0 && usdtBalance > 0) {
                markingContract.buy(
                    usdtBalance >= buyAmount ? buyAmount : usdtBalance
                );
            }
        }
    }

    /**
     * 计算需要卖出的代币数量
     * @return 需要卖出的代币数量
     */
    function calculateSellAmount() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();

        uint256 reserveD3xai;
        uint256 reserveUsdt;

        if (token0 == address(this)) {
            reserveD3xai = uint256(reserve0);
            reserveUsdt = uint256(reserve1);
        } else {
            reserveD3xai = uint256(reserve1);
            reserveUsdt = uint256(reserve0);
        }

        if (reserveD3xai == 0 || reserveUsdt == 0 || marketControlPrice == 0) {
            return 0;
        }

        // 根据恒定乘积公式精确计算需要卖出的D3XAI数量
        // k = reserveD3xai * reserveUsdt
        // 卖出amountIn后: (reserveD3xai + amountIn * 997/1000) * (reserveUsdt - amountOut) = k
        // 目标价格: (reserveUsdt - amountOut) / (reserveD3xai + amountIn * 997/1000) = marketControlPrice / 1e18
        // 推导: amountIn = (sqrt(k * 1e18 / marketControlPrice) - reserveD3xai) * 1000 / 997

        uint256 k = reserveD3xai * reserveUsdt;
        uint256 targetReserveD3xai = sqrt((k * 1 ether) / marketControlPrice);

        if (targetReserveD3xai <= reserveD3xai) {
            return 0;
        }

        // 需要增加的D3XAI(扣除手续费后)
        uint256 deltaAfterFee = targetReserveD3xai - reserveD3xai;

        // 实际需要输入的D3XAI(扣除0.3%手续费前)
        return (deltaAfterFee * 1000) / 997;
    }

    /**
     * 计算需要买入的USDT数量
     * @return 需要买入的USDT数量
     */
    function calculateBuyAmount() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();

        uint256 reserveD3xai;
        uint256 reserveUsdt;

        if (token0 == address(this)) {
            reserveD3xai = uint256(reserve0);
            reserveUsdt = uint256(reserve1);
        } else {
            reserveD3xai = uint256(reserve1);
            reserveUsdt = uint256(reserve0);
        }

        if (reserveD3xai == 0 || reserveUsdt == 0 || marketControlPrice == 0) {
            return 0;
        }

        // 根据恒定乘积公式精确计算需要买入的USDT数量
        // k = reserveD3xai * reserveUsdt
        // 买入D3XAI输入amountIn USDT后: (reserveUsdt + amountIn * 997/1000) * (reserveD3xai - amountOut) = k
        // 目标价格: (reserveUsdt + amountIn * 997/1000) / (reserveD3xai - amountOut) = marketControlPrice / 1e18
        // 推导: amountIn = (sqrt(k * marketControlPrice / 1e18) - reserveUsdt) * 1000 / 997

        uint256 k = reserveD3xai * reserveUsdt;
        uint256 targetReserveUsdt = sqrt((k * marketControlPrice) / 1 ether);

        if (targetReserveUsdt <= reserveUsdt) {
            return 0;
        }

        // 需要增加的USDT(扣除手续费后)
        uint256 deltaAfterFee = targetReserveUsdt - reserveUsdt;

        // 实际需要输入的USDT(扣除0.3%手续费前)
        return (deltaAfterFee * 1000) / 997;
    }

    /**
     * 查询是否熔断
     * @return 是否熔断
     */
    function isBreakthrough() public view returns (bool) {
        uint256 currentPrice = price();
        return currentPrice < (highestPrice * 50) / 100;
    }

    /**
     * 单独的买入接口
     * @param _amount 买入数量
     */
    function buy(uint256 _amount) public {
        address user = _msgSender();
        // ! 限制白名单才能买入,注意下面的 inSwap
        require(whitelist[user], "only whitelist can buy"); // ! 只允许白名单买卖,搜索这个

        lastBuy[user] = block.timestamp; // ! 必须记录买入时间

        require(usdt.balanceOf(user) >= _amount, "Insufficient balance");
        require(
            usdt.allowance(user, address(this)) >= _amount,
            "Insufficient allowance"
        );
        require(
            usdt.transferFrom(user, address(this), _amount),
            "Transfer failed"
        );

        address[] memory path = new address[](2);
        path[0] = address(usdt);
        path[1] = address(this);

        uint256 minAmountOut = getMinAmountOut(_amount, path);

        uint256 beforeAmount = balanceOf(address(markingContract));
        inSwap = true;
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            minAmountOut,
            path,
            address(markingContract), // 只有先转到Marking合约再转给用户,不能直接转到本地和用户,因为要限制买入
            block.timestamp + 300
        );
        inSwap = false;
        uint256 afterAmount = balanceOf(address(markingContract));
        uint256 amount = afterAmount - beforeAmount;
        _transfer(address(markingContract), user, amount); // ! 使用这个不需要approve

        // 附加做市
        executeMarketControl();
    }

    /**
     * 内部卖出代币为USDT
     * @param _amount 卖出数量
     * @param _minAmount 最小输出数量
     * @param _to 卖出地址
     */
    function _sell(
        uint256 _amount,
        uint256 _minAmount,
        address _to
    ) internal returns (uint256) {
        require(_to != address(0), "to is 0");

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(usdt);

        uint256 beforeAmount = usdt.balanceOf(_to);
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            _minAmount,
            path,
            _to,
            block.timestamp + 300
        );
        uint256 afterAmount = usdt.balanceOf(_to);

        return afterAmount - beforeAmount;
    }

    /**
     * 单独的卖出接口
     * 增加了卖出限额,需要做买入后的时间限制,同时 _update 中也要有时间锁限制防止闪电贷
     * @param _amount 卖出数量
     */
    function sell(uint256 _amount) public buyCoolDown(_msgSender()) {
        revert("sell disabled"); // 使用 tokenSell 卖出
        address user = _msgSender();
        uint256 currentPrice = price();

        if (lastBuy[user] > 0) {
            require(
                lastBuy[user] + 10 seconds < block.timestamp,
                "last buy time"
            );
        }

        // ! 买入后限制转出和卖出,需要在2处做限制
        if (lastBuy[user] > 0 && !whitelist[user]) {
            require(
                lastBuy[user] + 10 seconds < block.timestamp,
                "last buy time"
            );
        }

        // ! 暂时关闭熔断
        // 更新最高价
        // if (currentPrice > highestPrice) {
        //     highestPrice = currentPrice;
        // }

        // ##### 下面是限制转出部分 #####

        // 计算总价值
        uint256 totalUsd = (_amount * currentPrice) / 1 ether;

        // ! 每个地址每日限额
        uint256 windowStart = transferDailyWindowStart[user];
        if (windowStart == 0 || block.timestamp >= windowStart + 1 days) {
            transferDailyWindowStart[user] = block.timestamp;
            transferDailyAmount[user] = 0;
        }

        if (
            transferDailyWindowStart[address(this)] == 0 ||
            block.timestamp >= transferDailyWindowStart[address(this)] + 1 days
        ) {
            transferDailyWindowStart[address(this)] = block.timestamp;
            dailyTradeVolume = 0;
        }

        bool isTestnet = block.chainid == 97;

        // ! 平台总限额
        if (dailyTradeLimit > 0 && !isTestnet) {
            require(
                dailyTradeVolume + totalUsd <= dailyTradeLimit,
                "daily trade volume exceeded"
            );
        }
        if (transferDailyLimit > 0 && !isTestnet) {
            require(
                transferDailyAmount[user] + totalUsd <= transferDailyLimit,
                "daily limit exceeded"
            );
        }

        dailyTradeVolume += totalUsd;
        transferDailyAmount[user] += totalUsd;

        // ##### 上面是限额部分 #####

        // 如果 当前价格低于最高价50%则直接给用户销毁而不是卖出
        if (isBreakthrough()) {
            _burn(user, _amount);
            return;
        }

        _transfer(user, address(this), _amount);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(usdt);

        // 卖出手续滑点7.5%,要卖成USDT,LP捐赠分红(就是一个提现地址)5%,平台预留2.5%(一个新地址)
        // 白名单也要收取手续费

        // ! 手续费比例有2个地方需要修改,搜索这个

        // ! 提现地址 3.5% 用于LP捐赠分红
        uint256 lpDonationAmount = (_amount * 35) / 1000;
        uint256 minLpDonationAmount = getMinAmountOut(lpDonationAmount, path);
        uint256 lpWithdrawAmount = _sell(
            lpDonationAmount,
            minLpDonationAmount,
            withdrawAddress
        );
        emit WithdrawFee(withdrawAddress, lpDonationAmount, lpWithdrawAmount);

        // ! 剩下的卖出给用户
        uint256 remainingAmount = _amount - lpDonationAmount;
        uint256 minRemainingAmount = getMinAmountOut(remainingAmount, path);
        _sell(remainingAmount, minRemainingAmount, user);

        // 附加做市
        executeMarketControl();
    }

    /**
     * 计算最小输出数量(考虑滑点,5%)
     * @param _amountIn 输入数量
     * @param _path 交易路径
     */
    function getMinAmountOut(
        uint256 _amountIn,
        address[] memory _path
    ) internal view returns (uint256) {
        uint256[] memory amountsOut = pancakeRouter.getAmountsOut(
            _amountIn,
            _path
        );
        uint256 expectedOut = amountsOut[amountsOut.length - 1];

        // 应用滑点保护 10%
        return (expectedOut * (10000 - 1000)) / 10000;
    }

    /**
     * 重写_update,防止合约调用导致的攻击,例如闪电贷
     * @param from 转出地址
     * @param to 转入地址
     * @param value 数量
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (inSwap) {
            super._update(from, to, value);
            return;
        }

        // ! 增加总量限制防止意外增发无限铸造
        if (from == address(0) && block.chainid == 56) {
            require(
                value + totalSupply() <= TOTAL_SUPPLY,
                "Total supply limit"
            );
        }

        // ! 直接允许流动性合约买卖
        if (
            liquidityContract != address(0) &&
            (from == address(liquidityContract) ||
                to == address(liquidityContract))
        ) {
            super._update(from, to, value);
            return;
        }
        // ! 允许Marking合约买卖
        else if (
            address(markingContract) != address(0) &&
            (from == address(markingContract) || to == address(markingContract))
        ) {
            super._update(from, to, value);
            return;
        }
        // ! 允许 pancakeBuyer 合约买卖
        else if (
            address(pancakeBuyer) != address(0) &&
            (from == address(pancakeBuyer) || to == address(pancakeBuyer))
        ) {
            super._update(from, to, value);
            return;
        }
        // ! 允许 buy 合约买卖
        else if (
            address(buyContract) != address(0) &&
            (from == address(buyContract) || to == address(buyContract))
        ) {
            super._update(from, to, value);
            return;
        }
        // ! 允许 birdBuy 合约买卖
        else if (
            address(birdBuy) != address(0) &&
            (from == address(birdBuy) || to == address(birdBuy))
        ) {
            super._update(from, to, value);
            return;
        }
        // ! 允许 synthesisBuy 合约买卖
        else if (
            address(synthesisBuy) != address(0) &&
            (from == address(synthesisBuy) || to == address(synthesisBuy))
        ) {
            super._update(from, to, value);
            return;
        }

        // ! 限制买入时间,防止闪电贷
        if (address(pair) != address(0)) {
            bool isBuy = from == address(pair);
            bool isSell = to == address(pair);
            if (isBuy) {
                require(whitelist[to], "not whitelist"); // ! 只允许白名单买卖,搜索这个

                lastBuy[to] = block.timestamp; // ! 必须记录买入时间

                // 记录最高价 - 移除价格调用避免重入，改为在sell函数中更新
            }

            if (isSell) {
                // ! 需要禁止其他地址卖出
                require(whitelist[from], "not whitelist"); // ! 只允许白名单买卖
            }
        }

        // ! 使用时间限制防止闪电贷
        if (from != address(0) && lastBuy[from] > 0 && !whitelist[from]) {
            require(
                lastBuy[from] + 10 seconds < block.timestamp,
                "last buy time"
            );
        }

        super._update(from, to, value);
    }

    /**
     * 管理员批量添加白名单
     * @param _addresses 白名单地址数组
     */
    function batchAddWhitelist(
        address[] memory _addresses
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = true;
        }
    }

    /**
     * 管理员设置历史最高价和当前开盘价
     * @param _highestPrice 历史最高价
     * @param _dailyOpenPrice 当前开盘价
     */
    function setHighestPrice(
        uint256 _highestPrice,
        uint256 _dailyOpenPrice
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        highestPrice = _highestPrice;
        if (_dailyOpenPrice > 0) {
            dailyOpenPrice = _dailyOpenPrice;
        }
    }

    /**
     * 管理员批量移除白名单
     * @param _addresses 白名单地址数组
     */
    function batchRemoveWhitelist(
        address[] memory _addresses
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = false;
        }
    }

    /**
     * 管理员执行自动化配置
     * ! 有一些不能写在里面,比如随时改动的手续费,只能写入固定的,或者判断没有初始化再初始化
     */
    function todo() public onlyRole(DEFAULT_ADMIN_ROLE) {
        bool isTestnet = block.chainid == 97;
        if (address(pancakeRouter) == address(0)) {
            pancakeRouter = IPancakeRouter02(
                isTestnet
                    ? 0xD99D1c33F9fC3444f8101754aBC46c52416550D1
                    : 0x10ED43C718714eb63d5aA57B78B54704E256024E
            );
        }
        if (address(usdt) == address(0)) {
            usdt = IERC20(
                isTestnet
                    ? 0xCD582Fe937ed0b0235432810A790933db32896F2
                    : 0x55d398326f99059fF775485246999027B3197955
            );
        }
        if (dailyTradeLimit == 0) {
            dailyTradeLimit = 60000 ether;
        }
        if (transferDailyLimit == 0) {
            transferDailyLimit = 10000 ether;
        }

        whitelist[_msgSender()] = true;
        whitelist[address(this)] = true;
        whitelist[address(pair)] = true;
        whitelist[address(synthesisBuy)] = true;

        // 将Marking合约加入白名单
        if (address(markingContract) != address(0)) {
            whitelist[address(markingContract)] = true;
        }

        if (highestPrice == 0) {
            highestPrice = price();
        }

        // 初始化开盘价
        if (dailyOpenPrice == 0) {
            dailyOpenPrice = price();
            dailyPriceWindowStart = block.timestamp;
        }

        uint256 d3xaiAllowance = allowance(
            address(this),
            address(pancakeRouter)
        );
        if (d3xaiAllowance == 0) {
            _approve(address(this), address(pancakeRouter), type(uint256).max);
        }

        uint256 usdtAllowance = usdt.allowance(
            address(this),
            address(pancakeRouter)
        );
        if (usdtAllowance == 0) {
            usdt.approve(address(pancakeRouter), type(uint256).max);
        }

        if (address(markingContract) == address(0)) {
            markingContract = IMarking(
                isTestnet
                    ? 0xa592382dd75E655b4566CD4d1a6F2e5F208DE774
                    : 0x058b3d14D4F2FEa7E7EB42165d55dD0Bf34fb609
            );
        }

        if (address(withdrawAddress) == address(0)) {
            withdrawAddress = isTestnet
                ? 0xC86e4D4ED5065d6000B2d8089Dc41B4970aAB0b2
                : 0x070c9A4BE5798bFf3Bb90d51525B35E34099859c;
        }
        whitelist[withdrawAddress] = true;

        if (address(liquidityContract) == address(0)) {
            liquidityContract = isTestnet
                ? 0xdFbe616EcD73cBdC36ED822d8A1E3a2445ca60D5
                : 0xa74dEC366f7380CdFa586EcE5f8a343EEf1091Ba;
        }

        if (address(pancakeBuyer) == address(0)) {
            pancakeBuyer = isTestnet
                ? 0x8d76fff94819eCa7A28c1bDfa6BE5b08f45252CA
                : 0x60BeEECA8A3d45328E977a779234e3ae09ee9ffc;
        }

        if (address(fiveFeeAddress) == address(0)) {
            fiveFeeAddress = isTestnet
                ? 0x796Cfc73700a4773D93D8c9c8280D3eb57Ed8613
                : 0xd6b09b1e91dCa2A1203a80529c3a656a17d00578;
        }

        birdBuy = address(
            isTestnet
                ? 0xbFc5DfF9D546d7a2C2E587925e5B0c4cac7A05B2
                : 0xB1D5A5b7F017D2bD161Aaf93d719D4351B25cC78
        );

        if (address(synthesisBuy) == address(0)) {
            synthesisBuy = isTestnet
                ? 0xE2b1a710eA3849E5261f89b13627D146b86f1D32
                : 0x284B79C0DaC0F14758FE309F776C39c0A0F93114;
        }

        if (address(buyContract) == address(0)) {
            buyContract = isTestnet
                ? 0x69fE4693aEcD2d315Cf442d876B64C7C52Abf68f
                : 0x3C0A32DC41DaA24fc432ECE663C1E2FEB43ba497;
        }

        tokenSellContract = isTestnet
            ? 0x693a80a16cd2893003f31A0376628bf3b009011E
            : 0xE0f46F74f312DA82054d867d30827672b7260B3c;
        // ! 提供权限给 tokenSellContract 合约
        _grantRole(SELL_ROLE, address(tokenSellContract));
        whitelist[address(tokenSellContract)] = true;
    }

    /**
     * 健康检查
     */
    function healthcheck() public view onlyRole(DEFAULT_ADMIN_ROLE) {
        // 1. 检查是否在允许的测试网 1,56 必须不能在 allowTestChainId 中
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 1;
        chainIds[1] = 56;
        for (uint256 i = 0; i < chainIds.length; i++) {
            for (uint256 j = 0; j < allowTestChainId.length; j++) {
                if (allowTestChainId[j] == chainIds[i]) {
                    revert("testnet chainid is not allowed");
                }
            }
        }
        require(address(withdrawAddress) != address(0), "withdrawAddress is 0");
        require(
            address(liquidityContract) != address(0),
            "liquidityContract is 0"
        );
        require(pancakeBuyer != address(0), "pancakeBuyer is 0");
        require(fiveFeeAddress != address(0), "fiveFeeAddress is 0");
        require(address(birdBuy) != address(0), "birdBuy is not set");
        require(address(synthesisBuy) != address(0), "synthesisBuy is not set");
        require(address(buyContract) != address(0), "buy is not set");
        require(
            address(tokenSellContract) != address(0),
            "tokenSellContract is not set"
        );
    }
}
