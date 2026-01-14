// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/mc/MC.sol";
import "../../src/mc/TaxDistributor.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

interface IPancakePair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

// 定义 ERC20 Transfer 事件用于测试断言
event Transfer(address indexed from, address indexed to, uint256 value);

contract MCTest is Test {
    MC public mc;
    TaxDistributor public distributor;
    IERC20 public usdt;

    address public owner;
    address public taxWallet1;
    address public taxWallet2;
    address public taxWallet3;
    address public alice;
    address public bob;
    address public pair;

    address public constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address public constant USDT_ADDR =
        0x55d398326f99059fF775485246999027B3197955;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        // Fork BSC主网
        vm.createSelectFork("https://bsc-dataseed.binance.org");

        owner = address(this);
        taxWallet1 = address(0x111);
        taxWallet2 = address(0x222);
        taxWallet3 = address(0x333);
        alice = address(0xA11CE);
        bob = address(0xB0B);

        usdt = IERC20(USDT_ADDR);

        // 1. 部署MC合约
        mc = new MC(taxWallet1, taxWallet2, taxWallet3);
        console.log(unicode"=== 步骤1: 部署MC合约 ===");
        console.log(unicode"MC地址:");
        console.logAddress(address(mc));

        // 2. 创建MC/USDT交易对
        pair = mc.createPair(ROUTER);
        mc.setPair(pair, true);
        console.log(unicode"Pair地址:");
        console.logAddress(pair);

        // 3. 添加流动性
        _addLiquidity();

        // 4. 部署TaxDistributor合约
        distributor = new TaxDistributor(
            address(mc),
            ROUTER,
            taxWallet1,
            taxWallet2,
            taxWallet3
        );
        mc.setTaxDistributor(address(distributor));
        console.log(unicode"TaxDistributor地址:");
        console.logAddress(address(distributor));

        // 5. 给alice分配MC和USDT
        mc.transfer(alice, 1_000_000 ether);
        deal(USDT_ADDR, alice, 100_000 ether, true);

        console.log(unicode"Alice MC余额:", mc.balanceOf(alice) / 1e18);
        console.log(unicode"Alice USDT余额:", usdt.balanceOf(alice) / 1e18);
        _logPrice(unicode"初始价格");
    }

    function _addLiquidity() internal {
        uint256 mcAmount = 10_000_000 ether;
        uint256 usdtAmount = 10_000_000 ether;

        // 给测试合约添加 USDT 用于添加流动性
        deal(USDT_ADDR, address(this), usdtAmount, true);

        // approve Router to spend MC and USDT
        mc.approve(ROUTER, type(uint256).max);
        usdt.approve(ROUTER, type(uint256).max);

        // 使用 Router 的 addLiquidity 添加流动性
        IPancakeRouter(ROUTER).addLiquidity(
            address(mc),
            USDT_ADDR,
            mcAmount,
            usdtAmount,
            mcAmount, // amountAMin
            usdtAmount, // amountBMin
            address(this), // LP tokens 发送到测试合约
            block.timestamp
        );

        console.log(unicode"添加流动性完成");
    }

    // 辅助函数: 执行 swap
    function _doSwap(
        uint256 amountIn,
        address[] memory path,
        address to
    ) internal returns (bool success) {
        (success, ) = ROUTER.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                amountIn,
                0,
                path,
                to,
                block.timestamp
            )
        );
    }

    // 辅助函数: 获取 1 MC = ? USDT
    function _getMCPrice() internal view returns (uint256 priceInUSDT) {
        (uint112 reserve0, uint112 reserve1, ) = IPancakePair(pair)
            .getReserves();
        address token0Addr = IPancakePair(pair).token0();

        // 两个代币都是 18 位小数,所以储备金比值直接就是价格
        if (token0Addr == USDT_ADDR) {
            // token0 = USDT, token1 = MC
            // 1 MC = reserve0 / reserve1 USDT
            priceInUSDT = (uint256(reserve0) * 1e18) / uint256(reserve1);
        } else {
            // token0 = MC, token1 = USDT
            // 1 MC = reserve1 / reserve0 USDT
            priceInUSDT = (uint256(reserve1) * 1e18) / uint256(reserve0);
        }
    }

    // 辅助函数: 显示价格
    function _logPrice(string memory label) internal view {
        uint256 price = _getMCPrice();
        uint256 whole = price / 1e18;
        uint256 fraction = (price % 1e18) / 1e14; // 4位小数
        // 格式化分数部分,确保显示4位
        string memory fracStr = _toString(fraction);
        if (bytes(fracStr).length < 4) {
            uint256 padding = 4 - bytes(fracStr).length;
            bytes memory padded = new bytes(4);
            for (uint256 i = 0; i < padding; i++) {
                padded[i] = bytes1("0");
            }
            for (uint256 i = 0; i < bytes(fracStr).length; i++) {
                padded[padding + i] = bytes(fracStr)[i];
            }
            fracStr = string(padded);
        }
        console.log(unicode"%s: %s.%s USDT", label, _toString(whole), fracStr);
    }

    // 辅助函数: uint256 转 string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // ========== 测试1: 通过swap买入MC (USDT -> MC) ==========

    function test_BuyViaSwap() public {
        mc.setTradingEnabled(true);

        // Alice approve Router
        vm.prank(alice);
        usdt.approve(ROUTER, type(uint256).max);

        uint256 usdtAmount = 100 ether;
        uint256 mcBefore = mc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);

        console.log(unicode"=== 测试1: 通过swap买入MC ===");
        console.log(unicode"买入前 MC余额:", mcBefore / 1e18);
        console.log(unicode"买入前 USDT余额:", usdtBefore / 1e18);
        _logPrice(unicode"买入前价格");

        // Alice通过swap买入MC
        address[] memory path = new address[](2);
        path[0] = USDT_ADDR;
        path[1] = address(mc);

        vm.prank(alice);
        bool success = _doSwap(usdtAmount, path, alice);
        require(success, "Swap failed");

        uint256 mcAfter = mc.balanceOf(alice);
        uint256 usdtAfter = usdt.balanceOf(alice);
        uint256 mcReceived = mcAfter - mcBefore;
        uint256 usdtSpent = usdtBefore - usdtAfter;

        _logPrice(unicode"买入后价格");
        console.log(unicode"买入后 MC余额:", mcAfter / 1e18);
        console.log(unicode"买入后 USDT余额:", usdtAfter / 1e18);
        console.log(unicode"实际支付USDT:", usdtSpent / 1e18);
        console.log(unicode"实际收到MC:", mcReceived / 1e18);

        // 断言: USDT减少, MC增加
        assertEq(usdtSpent, usdtAmount, "USDT amount mismatch");
        assertGt(mcReceived, 0, "MC should increase");
        console.log(unicode"✓ 买入成功,无手续费");
    }

    // ========== 测试2: 通过swap卖出MC (MC -> USDT) ==========

    function test_SellViaSwap() public {
        mc.setTradingEnabled(true);

        // Alice approve Router
        vm.prank(alice);
        mc.approve(ROUTER, type(uint256).max);

        uint256 sellAmount = 10000 ether;

        // 记录初始余额
        uint256 mcBefore = mc.balanceOf(alice);
        uint256 usdtBefore = usdt.balanceOf(alice);
        uint256 tax1McBefore = mc.balanceOf(taxWallet1);
        uint256 tax2McBefore = mc.balanceOf(taxWallet2);
        uint256 tax3McBefore = mc.balanceOf(taxWallet3);
        uint256 tax1UsdtBefore = usdt.balanceOf(taxWallet1);
        uint256 tax2UsdtBefore = usdt.balanceOf(taxWallet2);
        uint256 tax3UsdtBefore = usdt.balanceOf(taxWallet3);
        uint256 deadBefore = mc.balanceOf(DEAD);
        uint256 pairBefore = mc.balanceOf(pair);

        console.log(unicode"=== 测试2: 通过swap卖出MC ===");
        console.log(unicode"卖出前 MC余额:", mcBefore / 1e18);
        console.log(unicode"卖出前 USDT余额:", usdtBefore / 1e18);
        _logPrice(unicode"卖出前价格");

        // Alice通过swap卖出MC
        address[] memory path = new address[](2);
        path[0] = address(mc);
        path[1] = USDT_ADDR;

        vm.prank(alice);
        bool success = _doSwap(sellAmount, path, alice);
        require(success, "Swap failed");

        // 触发税收分发
        distributor.distributeTax();

        _logPrice(unicode"卖出后价格");

        // 显示余额变化
        console.log(unicode"卖出后 MC余额:", mc.balanceOf(alice) / 1e18);
        console.log(unicode"卖出后 USDT余额:", usdt.balanceOf(alice) / 1e18);
        console.log(unicode"实际卖出MC:", sellAmount / 1e18);
        console.log(unicode"实际收到USDT:", (usdt.balanceOf(alice) - usdtBefore) / 1e18);

        // 税收分配 - 钱包收到的是USDT
        console.log(unicode"卖出MC数量:", sellAmount / 1e18);
        console.log(unicode"钱包1 USDT收入:", (usdt.balanceOf(taxWallet1) - tax1UsdtBefore) / 1e18);
        console.log(unicode"钱包2 USDT收入:", (usdt.balanceOf(taxWallet2) - tax2UsdtBefore) / 1e18);
        console.log(unicode"钱包3 USDT收入:", (usdt.balanceOf(taxWallet3) - tax3UsdtBefore) / 1e18);
        console.log(unicode"黑洞 (3%):", (mc.balanceOf(DEAD) - deadBefore) / 1e18);
        console.log(unicode"交易对收到:", (mc.balanceOf(pair) - pairBefore) / 1e18);

        // 验证: 钱包不收到MC,而是收到USDT
        assertEq(mc.balanceOf(taxWallet1), tax1McBefore, unicode"钱包1不应收到MC");
        assertEq(mc.balanceOf(taxWallet2), tax2McBefore, unicode"钱包2不应收到MC");
        assertEq(mc.balanceOf(taxWallet3), tax3McBefore, unicode"钱包3不应收到MC");
        assertGt(usdt.balanceOf(taxWallet1), tax1UsdtBefore, unicode"钱包1应收到USDT");
        assertGt(usdt.balanceOf(taxWallet2), tax2UsdtBefore, unicode"钱包2应收到USDT");
        assertGt(usdt.balanceOf(taxWallet3), tax3UsdtBefore, unicode"钱包3应收到USDT");
        assertEq(mc.balanceOf(DEAD) - deadBefore, 300 ether);
        // Pair 收到 Alice 的 9000 MC + TaxDistributor swap 进来的 700 MC = 9700 MC
        assertEq(mc.balanceOf(pair) - pairBefore, 9700 ether);

        console.log(unicode"✓ 卖出手续费自动换成USDT");
    }

    // ========== 测试3: 白名单swap卖出不收税 ==========

    function test_WhitelistSellNoTax() public {
        mc.setTradingEnabled(true);
        mc.setWhitelist(alice, true);

        vm.prank(alice);
        mc.approve(ROUTER, type(uint256).max);

        uint256 deadBefore = mc.balanceOf(DEAD);
        uint256 pairBefore = mc.balanceOf(pair);
        uint256 sellAmount = 1000 ether;

        // 白名单用户卖出
        address[] memory path = new address[](2);
        path[0] = address(mc);
        path[1] = USDT_ADDR;

        vm.prank(alice);
        bool success = _doSwap(sellAmount, path, alice);
        require(success, "Swap failed");

        // 白名单不收税,pair应收到全部
        assertEq(mc.balanceOf(pair), pairBefore + sellAmount);
        assertEq(mc.balanceOf(DEAD), deadBefore);

        console.log(unicode"=== 测试3: 白名单卖出 ===");
        console.log(unicode"✓ 白名单用户swap卖出不收税");
    }

    // ========== 测试4: 销毁阈值 ==========

    function test_BurnThreshold() public {
        mc.setTradingEnabled(true);

        console.log(unicode"=== 测试4: 销毁阈值 ===");

        // 正常销毁
        vm.prank(alice);
        mc.approve(ROUTER, type(uint256).max);

        uint256 deadBefore = mc.balanceOf(DEAD);
        uint256 sellAmount = 1000 ether;

        address[] memory path = new address[](2);
        path[0] = address(mc);
        path[1] = USDT_ADDR;

        vm.prank(alice);
        bool success = _doSwap(sellAmount, path, alice);
        require(success, "Swap failed");

        uint256 burned = mc.balanceOf(DEAD) - deadBefore;
        assertEq(burned, 30 ether);
        console.log(unicode"✓ 正常销毁3%到黑洞");

        // 达到阈值
        deal(address(mc), DEAD, 12_000_000 ether, true);

        deadBefore = mc.balanceOf(DEAD);
        uint256 tax1Before = mc.balanceOf(taxWallet1);
        uint256 distributorBefore = mc.balanceOf(address(distributor));
        uint256 pairBefore = mc.balanceOf(pair);

        vm.prank(alice);
        success = _doSwap(sellAmount, path, alice);
        require(success, "Swap failed");

        uint256 tax1Received = mc.balanceOf(taxWallet1) - tax1Before;
        uint256 deadReceived = mc.balanceOf(DEAD) - deadBefore;
        uint256 distributorReceived = mc.balanceOf(address(distributor)) - distributorBefore;
        uint256 pairReceived = mc.balanceOf(pair) - pairBefore;

        // 达到阈值后: 0%黑洞, 7%转发到TaxDistributor
        // pair收到的 = 1000 - 70 = 930, TaxDistributor收到 70
        assertEq(tax1Received, 0); // 钱包不直接收到MC
        assertEq(deadReceived, 0); // 不再销毁
        assertEq(distributorReceived, 70 ether); // TaxDistributor收到7%
        assertEq(pairReceived, 930 ether); // 税率降为7%
        console.log(unicode"✓ 达到阈值后停止销毁,税率降为7%");
    }

    // ========== 测试5: 交易开关 ==========

    function test_TradingToggle() public {
        console.log(unicode"=== 测试5: 交易开关 ===");

        // 交易关闭时不能swap
        vm.prank(alice);
        mc.approve(ROUTER, type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(mc);
        path[1] = USDT_ADDR;

        // 低级 call 返回 false 而不是 revert
        vm.prank(alice);
        (bool success, ) = ROUTER.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                100 ether,
                0,
                path,
                alice,
                block.timestamp
            )
        );
        assertEq(success, false, "Swap should fail when trading is disabled");

        // 开启交易
        mc.setTradingEnabled(true);

        // 现在可以swap
        vm.prank(alice);
        success = _doSwap(100 ether, path, alice);
        require(success, "Swap failed");

        console.log(unicode"✓ 交易开关功能正常");
    }

    // ========== 测试6: 基本转账功能 ==========

    function test_BasicTransfer() public {
        mc.setTradingEnabled(true);

        uint256 transferAmount = 100 ether;

        // 记录转账前余额
        uint256 aliceBefore = mc.balanceOf(alice);
        uint256 bobBefore = mc.balanceOf(bob);

        console.log(unicode"=== 测试6: 基本转账 ===");
        console.log(unicode"转账前 Alice余额:", aliceBefore / 1e18);
        console.log(unicode"转账前 Bob余额:", bobBefore / 1e18);
        console.log(unicode"转账金额:", transferAmount / 1e18);

        // 预期 Transfer 事件
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, transferAmount);

        // Alice 转账给 Bob
        vm.prank(alice);
        mc.transfer(bob, transferAmount);

        // 记录转账后余额
        uint256 aliceAfter = mc.balanceOf(alice);
        uint256 bobAfter = mc.balanceOf(bob);

        console.log(unicode"转账后 Alice余额:", aliceAfter / 1e18);
        console.log(unicode"转账后 Bob余额:", bobAfter / 1e18);
        console.log(unicode"Alice减少:", (aliceBefore - aliceAfter) / 1e18);
        console.log(unicode"Bob增加:", (bobAfter - bobBefore) / 1e18);

        // 断言: 余额变化正确
        assertEq(aliceBefore - aliceAfter, transferAmount, "Alice balance should decrease");
        assertEq(bobAfter - bobBefore, transferAmount, "Bob balance should increase");

        console.log(unicode"✓ 基本转账功能正常");
    }
}
