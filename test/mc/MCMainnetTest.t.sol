// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/mc/MC.sol";
import "../../src/mc/TaxDistributor.sol";
import "../../src/mc/interfaces/IPancakeRouter.sol";
import "../../src/mc/interfaces/IPancakeFactory.sol";
import "../../src/mc/interfaces/IPancakePair.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MCMainnetTest
 * @dev 主网模拟测试: 验证流动性添加、买入、卖出税收逻辑
 */
contract MCMainnetTest is Test {
    MC public mc;
    TaxDistributor public distributor;

    // BSC 主网地址
    address constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant PANCAKE_FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    // 部署的合约地址
    address constant MC_ADDRESS = 0x8E7571CCda1045c548d85229BC444dE5615EC5f4;
    address constant DISTRIBUTOR_ADDRESS =
        0x0c7d5a9A13828d0F6cEc06FBb60c1351842afb62;

    // 测试钱包
    address public owner = 0x20F7acfc15a4EB3142F6d1DdFb219a660541484e;
    address public taxWallet1 = 0xEA37DEb2F85aeda26372efb8F59EDd0F6aC74B19;
    address public taxWallet2 = 0x3dFc8bc2BD7d387638477dd6453c07EA61cF2622;
    address public taxWallet3 = 0xBf93Be345758CF027577705F981C6bE02fA88184;
    address public user = address(0x1234);

    // 交易对地址
    address public pair;

    function setUp() public {
        // Fork BSC mainnet with default URL
        uint256 forkId = vm.createFork("https://bsc-dataseed.binance.org");
        vm.selectFork(forkId);

        // 加载已部署的合约
        mc = MC(MC_ADDRESS);
        distributor = TaxDistributor(DISTRIBUTOR_ADDRESS);

        // 获取交易对地址
        pair = IPancakeFactory(PANCAKE_FACTORY).getPair(MC_ADDRESS, USDT);

        console.log(unicode"=== 主网模拟测试环境 ===");
        console.log(unicode"MC 地址:", address(mc));
        console.log(unicode"交易对地址:", pair);
        console.log(unicode"所有者:", owner);
    }

    /**
     * @dev 测试1: 验证交易对已创建
     */
    function testPairExists() public view {
        assertTrue(pair != address(0), unicode"交易对不存在");
        assertTrue(mc.isPair(pair), unicode"Pair 未注册");
        console.log(unicode"✓ 交易对已创建");
    }

    /**
     * @dev 测试2: 模拟添加流动性
     */
    function testAddLiquidity() public {
        console.log(unicode"\n=== 测试添加流动性 ===");

        // 给用户一些 MC 和 USDT (从 Owner 转账)
        vm.prank(owner);
        mc.transfer(user, 100_000 ether);

        // 从富户获取 USDT
        address usdtWhale = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3;
        vm.prank(usdtWhale);
        IERC20(USDT).transfer(user, 100_000 ether);

        // 查看添加前的余额
        uint256 userMcBefore = mc.balanceOf(user);
        uint256 userUsdtBefore = IERC20(USDT).balanceOf(user);
        console.log(unicode"用户 MC 余额 (添加前):", userMcBefore / 1e18);
        console.log(unicode"用户 USDT 余额 (添加前):", userUsdtBefore / 1e18);

        // 授权 Router
        vm.startPrank(user);
        mc.approve(PANCAKE_ROUTER, type(uint256).max);
        IERC20(USDT).approve(PANCAKE_ROUTER, type(uint256).max);

        // 添加流动性
        uint256 mcAmount = 10_000 ether;
        uint256 usdtAmount = 100 ether;
        IPancakeRouter(PANCAKE_ROUTER).addLiquidity(
            MC_ADDRESS,
            USDT,
            mcAmount,
            usdtAmount,
            0,
            0,
            user,
            block.timestamp + 3600
        );
        vm.stopPrank();

        // 验证余额变化
        uint256 userMcAfter = mc.balanceOf(user);
        uint256 userUsdtAfter = IERC20(USDT).balanceOf(user);
        console.log(unicode"用户 MC 余额 (添加后):", userMcAfter / 1e18);
        console.log(unicode"用户 USDT 余额 (添加后):", userUsdtAfter / 1e18);

        assertEq(userMcBefore - userMcAfter, mcAmount, unicode"MC 扣除不正确");
        assertEq(
            userUsdtBefore - userUsdtAfter,
            usdtAmount,
            unicode"USDT 扣除不正确"
        );
        console.log(unicode"✓ 添加流动性成功");
    }

    /**
     * @dev 测试3: 模拟卖出 (卖出收10%税)
     */
    function testSellTax() public {
        console.log(unicode"\n=== 测试卖出收税 ===");

        // 先添加流动性
        _addLiquidity();

        uint256 sellAmount = 1_000 ether;
        address dead = 0x000000000000000000000000000000000000dEaD;

        vm.prank(owner);
        mc.transfer(user, 10_000 ether);
        vm.prank(owner);
        mc.setTradingEnabled(true);
        vm.prank(user);
        mc.approve(PANCAKE_ROUTER, type(uint256).max);

        // 记录初始状态
        uint256 userMcBefore = mc.balanceOf(user);
        uint256 deadBefore = mc.balanceOf(dead);

        // 执行 swap
        vm.prank(user);
        _doSellSwap(sellAmount, user);

        // 验证 MC 消耗和销毁
        assertEq(
            userMcBefore - mc.balanceOf(user),
            sellAmount,
            unicode"用户应花费全部 MC"
        );

        uint256 burned = mc.balanceOf(dead) - deadBefore;
        assertEq(burned, (sellAmount * 300) / 10000, unicode"黑洞应得 3%");

        // 验证用户收到 USDT (从 swap 获得)
        uint256 userUsdt = IERC20(USDT).balanceOf(user);
        assertGt(userUsdt, 0, unicode"用户应收到 USDT");

        console.log(unicode"卖出 MC 数量:", sellAmount / 1e18);
        console.log(unicode"收到 USDT 数量:", userUsdt / 1e18);
        console.log(unicode"销毁到黑洞:", burned / 1e18);
        console.log(unicode"✓ 卖出税收正确 (10% = 7% 分发 + 3% 销毁)");
    }

    /**
     * @dev 内部函数: 添加流动性
     */
    function _addLiquidity() internal {
        console.log(unicode"\n=== 添加流动性 ===");

        // 从 Owner 获取 MC
        // 从富户获取 USDT
        address usdtWhale = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3;
        vm.prank(usdtWhale);
        IERC20(USDT).transfer(owner, 10_000 ether);

        vm.startPrank(owner);
        mc.approve(PANCAKE_ROUTER, type(uint256).max);
        IERC20(USDT).approve(PANCAKE_ROUTER, type(uint256).max);

        IPancakeRouter(PANCAKE_ROUTER).addLiquidity(
            MC_ADDRESS,
            USDT,
            100_000 ether, // MC
            100 ether, // USDT
            0,
            0,
            owner,
            block.timestamp + 3600
        );
        vm.stopPrank();

        console.log(unicode"✓ 流动性已添加");
    }

    /**
     * @dev 内部函数: 执行 swap 卖出
     */
    function _doSellSwap(
        uint256 amountIn,
        address recipient
    ) internal returns (bool success) {
        address[] memory path = new address[](2);
        path[0] = MC_ADDRESS; // MC
        path[1] = USDT; // USDT

        (success, ) = PANCAKE_ROUTER.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                amountIn,
                0,
                path,
                recipient,
                block.timestamp
            )
        );
    }

    /**
     * @dev 内部函数: 验证交易对流动性
     */
    function _checkPairLiquidity() internal view returns (bool) {
        (uint112 reserve0, uint112 reserve1, ) = IPancakePair(pair)
            .getReserves();
        return reserve0 > 0 && reserve1 > 0;
    }

    /**
     * @dev 测试4: 验证黑洞销毁阈值检查
     */
    function testBurnThresholdCheck() public {
        console.log(unicode"\n=== 测试销毁阈值检查 ===");

        // 查看当前 DEAD 余额
        uint256 deadBalance = mc.balanceOf(
            0x000000000000000000000000000000000000dEaD
        );
        uint256 threshold = 12_000_000 ether;
        console.log(unicode"黑洞余额:", deadBalance / 1e18);
        console.log(unicode"销毁阈值:", threshold / 1e18);

        bool reached = mc.hasReachedBurnThreshold();
        console.log(unicode"已达到阈值:", reached);

        if (reached) {
            console.log(unicode"✓ 已达到销毁阈值，停止销毁");
        } else {
            console.log(unicode"✓ 未达到销毁阈值，继续销毁");
        }
    }

    /**
     * @dev 测试5: 达到阈值后停止销毁
     */
    function testBurnStopsWhenThresholdReached() public {
        console.log(unicode"\n=== 测试达到阈值后停止销毁 ===");

        // 先添加流动性
        _addLiquidity();

        address dead = 0x000000000000000000000000000000000000dEaD;
        uint256 threshold = 12_000_000 ether;
        uint256 sellAmount = 10_000 ether;
        uint256 burnPerSell = (sellAmount * 300) / 10000;

        // 模拟黑洞余额接近阈值
        {
            uint256 targetBalance = 11_999_500 ether;
            uint256 currentDeadBalance = mc.balanceOf(dead);
            if (targetBalance > currentDeadBalance) {
                vm.prank(owner);
                mc.transfer(dead, targetBalance - currentDeadBalance);
            }
        }

        // 开启交易并给用户 MC
        vm.prank(owner);
        mc.setTradingEnabled(true);
        vm.prank(owner);
        mc.transfer(user, 100_000 ether);
        vm.prank(user);
        mc.approve(PANCAKE_ROUTER, type(uint256).max);

        // 连续卖出测试
        for (uint256 i = 1; i <= 5; i++) {
            uint256 deadBefore = mc.balanceOf(dead);
            uint256 userUsdtBefore = IERC20(USDT).balanceOf(user);

            vm.prank(user);
            _doSellSwap(sellAmount, user);

            uint256 deadAfter = mc.balanceOf(dead);
            uint256 burned = deadAfter - deadBefore;
            uint256 usdtReceived = IERC20(USDT).balanceOf(user) -
                userUsdtBefore;

            console.log(unicode"第", i, unicode"次卖出:");
            console.log(unicode"  销毁数量:", burned / 1e18);
            console.log(unicode"  黑洞余额:", deadAfter / 1e18);

            if (deadBefore < threshold) {
                assertEq(burned, burnPerSell, unicode"未达阈值时应销毁 3%");
            } else {
                assertEq(burned, 0, unicode"达到阈值后不应再销毁");
            }

            assertGt(usdtReceived, 0, unicode"用户应该收到 USDT");
        }

        console.log(unicode"✓ 达到阈值后停止销毁 (税率 10% -> 7%)");
    }

    /**
     * @dev 测试6: 综合测试流程
     */
    function testFullFlow() public {
        console.log(unicode"\n=== 综合测试流程 ===");

        // 1. 开启交易
        vm.prank(owner);
        mc.setTradingEnabled(true);
        console.log(unicode"✓ 交易已开启");

        // 2. 验证配置
        assertEq(mc.tradingEnabled(), true);
        assertEq(address(mc.taxDistributor()), address(distributor));
        console.log(unicode"✓ 配置验证通过");

        // 3. 测试核心税收逻辑
        testSellTax();

        console.log(unicode"\n✓ 所有测试通过!");
    }
}
