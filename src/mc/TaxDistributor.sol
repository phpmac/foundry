// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPancakeRouter.sol";

/**
 * @title TaxDistributor
 * @dev 税收分发合约，将MC swap成USDT并分发给各钱包
 */
contract TaxDistributor is Ownable {
    // MC代币地址
    address public mcToken;
    // USDT地址 (BSC主网固定)
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    // PancakeSwap Router
    address public pancakeRouter;

    // 税收钱包
    address public taxWallet1;
    address public taxWallet2;
    address public taxWallet3;

    // 税收比例 (总和应为700，对应7%)
    uint256 public constant TAX_ADDR1 = 200; // 2%
    uint256 public constant TAX_ADDR2 = 300; // 3%
    uint256 public constant TAX_ADDR3 = 200; // 2%

    // 防重入锁
    bool private _inSwap;
    // 初始化标志
    bool private _initialized;

    // 事件
    event TaxDistributed(uint256 mcSwapped, uint256 usdtReceived);
    event RouterUpdated(address router);
    event TaxWalletsUpdated(address wallet1, address wallet2, address wallet3);

    constructor(
        address _mcToken,
        address _router,
        address _taxWallet1,
        address _taxWallet2,
        address _taxWallet3
    ) Ownable(msg.sender) {
        require(_mcToken != address(0), "Invalid MC token");
        require(_router != address(0), "Invalid router");
        require(
            _taxWallet1 != address(0) &&
                _taxWallet2 != address(0) &&
                _taxWallet3 != address(0),
            "Invalid wallet"
        );

        mcToken = _mcToken;
        pancakeRouter = _router;
        taxWallet1 = _taxWallet1;
        taxWallet2 = _taxWallet2;
        taxWallet3 = _taxWallet3;

        // 注意: 不在构造函数中调用 approve，因为 MC 可能还未完全初始化
        // 会在首次调用 distributeTax 时自动初始化
    }

    /**
     * @dev 内部函数: 确保 Router 已被授权
     */
    function _ensureApproval() internal {
        if (!_initialized) {
            // 先更新状态，防止重入
            _initialized = true;
            bool success = IERC20(mcToken).approve(
                pancakeRouter,
                type(uint256).max
            );
            require(success, "Approval failed");
        }
    }

    // 修饰符: 防止重入
    modifier lockTheSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    /**
     * @dev 设置Router
     */
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "Invalid router");

        address oldRouter = pancakeRouter;

        // 撤销旧Router的授权
        if (oldRouter != address(0)) {
            IERC20(mcToken).approve(oldRouter, 0);
        }

        // 更新状态
        pancakeRouter = _router;

        // 授权新Router
        IERC20(mcToken).approve(_router, type(uint256).max);

        emit RouterUpdated(_router);
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
     * @dev 从MC合约提取MC并分发
     * @notice 任何人都可以调用此函数
     */
    function distributeTax() external lockTheSwap {
        // 确保已授权 (首次调用时初始化)
        _ensureApproval();

        // 获取合约当前持有的MC数量
        uint256 mcBalance = IERC20(mcToken).balanceOf(address(this));
        if (mcBalance == 0) return;

        // 按税收比例计算各钱包应得的MC数量
        uint256 mcForWallet1 = (mcBalance * TAX_ADDR1) /
            (TAX_ADDR1 + TAX_ADDR2 + TAX_ADDR3);
        uint256 mcForWallet2 = (mcBalance * TAX_ADDR2) /
            (TAX_ADDR1 + TAX_ADDR2 + TAX_ADDR3);
        uint256 mcForWallet3 = mcBalance - mcForWallet1 - mcForWallet2; // 避免精度损失

        address[] memory path = new address[](2);
        path[0] = mcToken;
        path[1] = USDT;

        uint256 usdtBefore = IERC20(USDT).balanceOf(address(this));

        // 使用 swapExactTokensForTokens swap MC 到 USDT
        uint256[] memory amounts = IPancakeRouter(pancakeRouter)
            .swapExactTokensForTokens(
                mcBalance,
                0,
                path,
                address(this),
                block.timestamp
            );
        require(amounts.length >= 2 && amounts[1] > 0, "Swap failed");

        uint256 usdtReceived = IERC20(USDT).balanceOf(address(this)) -
            usdtBefore;

        // 按比例分发USDT
        if (mcForWallet1 > 0 && usdtReceived > 0) {
            uint256 usdtForWallet1 = (usdtReceived * mcForWallet1) / mcBalance;
            bool success = IERC20(USDT).transfer(taxWallet1, usdtForWallet1);
            require(success, "USDT transfer to wallet1 failed");
        }
        if (mcForWallet2 > 0 && usdtReceived > 0) {
            uint256 usdtForWallet2 = (usdtReceived * mcForWallet2) / mcBalance;
            bool success = IERC20(USDT).transfer(taxWallet2, usdtForWallet2);
            require(success, "USDT transfer to wallet2 failed");
        }
        if (mcForWallet3 > 0 && usdtReceived > 0) {
            uint256 usdtForWallet3 = (usdtReceived * mcForWallet3) / mcBalance;
            bool success = IERC20(USDT).transfer(taxWallet3, usdtForWallet3);
            require(success, "USDT transfer to wallet3 failed");
        }

        emit TaxDistributed(mcBalance, usdtReceived);
    }

    /**
     * @dev 提取合约中的代币 (仅owner)
     */
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        bool success = IERC20(token).transfer(owner(), amount);
        require(success, "Transfer failed");
    }

    /**
     * @dev 查看合约持有的MC数量
     */
    function getMCBalance() external view returns (uint256) {
        return IERC20(mcToken).balanceOf(address(this));
    }
}
