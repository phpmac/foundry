// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/mc/MC.sol";
import "../../src/mc/TaxDistributor.sol";
import "../../src/mc/interfaces/IPancakeRouter.sol";
import "../../src/mc/interfaces/IPancakeFactory.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract TaxDistributorTest is Test {
    MC public mc;
    TaxDistributor public distributor;
    IERC20 public usdt;

    address public taxWallet1 = address(0x111);
    address public taxWallet2 = address(0x222);
    address public taxWallet3 = address(0x333);

    address public constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant USDT_ADDR = 0x55d398326f99059fF775485246999027B3197955;
    address public constant FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    function setUp() public {
        vm.createSelectFork("https://bsc-dataseed.binance.org");

        usdt = IERC20(USDT_ADDR);

        // 部署MC合约
        mc = new MC(taxWallet1, taxWallet2, taxWallet3);

        // 创建MC/USDT交易对并添加流动性
        address pair = IPancakeFactory(FACTORY).createPair(address(mc), USDT_ADDR);
        mc.setPair(pair, true);

        // 给测试合约添加 USDT 用于添加流动性
        uint256 mcAmount = 100_000 ether;
        uint256 usdtAmount = 100_000 ether;
        deal(USDT_ADDR, address(this), usdtAmount, true);
        mc.approve(ROUTER, type(uint256).max);
        usdt.approve(ROUTER, type(uint256).max);
        IPancakeRouter(ROUTER).addLiquidity(
            address(mc),
            USDT_ADDR,
            mcAmount,
            usdtAmount,
            mcAmount,
            usdtAmount,
            address(this),
            block.timestamp
        );

        // 部署TaxDistributor合约
        distributor = new TaxDistributor(
            address(mc),
            ROUTER,
            taxWallet1,
            taxWallet2,
            taxWallet3
        );
        mc.setTaxDistributor(address(distributor));

        // 给distributor分配一些MC用于测试
        deal(address(mc), address(distributor), 1000 ether, true);

        // 开启交易并将 TaxDistributor 加入白名单
        mc.setTradingEnabled(true);
        mc.setWhitelist(address(distributor), true);

        console.log(unicode"MC余额:", mc.balanceOf(address(distributor)) / 1e18);
    }

    function test_Distribute() public {
        // 直接给 distributor USDT，跳过 swap
        deal(USDT_ADDR, address(distributor), 1000 ether, true);
        uint256 w1Before = usdt.balanceOf(taxWallet1);
        uint256 w2Before = usdt.balanceOf(taxWallet2);
        uint256 w3Before = usdt.balanceOf(taxWallet3);

        // 调用 distributeTax (应该直接分发现有的 USDT)
        distributor.distributeTax();

        console.log(unicode"钱包1 收到:", (usdt.balanceOf(taxWallet1) - w1Before) / 1e18);
        console.log(unicode"钱包2 收到:", (usdt.balanceOf(taxWallet2) - w2Before) / 1e18);
        console.log(unicode"钱包3 收到:", (usdt.balanceOf(taxWallet3) - w3Before) / 1e18);
    }
}
