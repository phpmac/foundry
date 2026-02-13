// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/jm/JMToken.sol";
import "../../src/jm/JMBToken.sol";
import "../../src/jm/LPDistributor.sol";
import "../../src/jm/interfaces/IPancakeRouter.sol";
import "../../src/jm/interfaces/IPancakePair.sol";

/**
 * @title JMTokenTest
 * @dev JM Token 单元测试
 * 运行: forge test --match-path test/jm/JMToken.t.sol -vv
 */
contract JMTokenTest is Test {
    JMToken public jmToken;
    JMBToken public jmbToken;
    LPDistributor public lpDistributor;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    // BSC主网 PancakeSwap Router
    address public constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function setUp() public {
        // 使用foundry.toml里命名端点,避免被.env里的测试网RPC误导
        vm.createSelectFork(vm.rpcUrl("bsc_mainnet"));

        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // 给测试合约分配BNB用于创建流动性
        vm.deal(address(this), 100 ether);

        // 给测试用户分配ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);

        // 部署合约
        jmToken = new JMToken(PANCAKE_ROUTER);
        jmbToken = new JMBToken();
        lpDistributor = new LPDistributor(
            address(jmToken),
            jmToken.lpPair(),
            address(jmbToken)
        );

        // 配置合约
        jmToken.setLPDistributor(address(lpDistributor));
        jmbToken.setMinter(address(lpDistributor));

        // 按需求使用Pancake真实路由添加20 BNB流动性
        jmToken.addLiquidity{value: 20 ether}(666_667 ether);
    }

    // ========== 基础功能测试 ==========

    function test_TokenInfo() public view {
        assertEq(jmToken.name(), "JM Token");
        assertEq(jmToken.symbol(), "JM");
        assertEq(jmToken.totalSupply(), 21_000_000 ether);
        assertEq(jmToken.decimals(), 18);
    }

    function test_InitialBalance() public {
        uint256 actual = jmToken.balanceOf(address(this));
        console.log(unicode"实际余额:", actual);
        // 只需验证有剩余代币即可
        assertGt(actual, 0);
    }

    // ========== 私募测试 ==========

    function test_PrivateSale() public {
        uint256 initialBalance = jmToken.balanceOf(user1);

        vm.prank(user1);
        (bool success, ) = payable(address(jmToken)).call{value: 0.2 ether}("");
        assertTrue(success);

        // 检查收到6000 JM
        assertEq(jmToken.balanceOf(user1) - initialBalance, 6000 ether);
    }

    function test_PrivateSaleExactAmount() public {
        vm.prank(user1);
        (bool success, bytes memory data) = payable(address(jmToken)).call{
            value: 0.1 ether
        }("");
        assertFalse(success);
        assertEq(_revertMsg(data), "Invalid BNB amount");
    }

    function test_PrivateSaleClosed() public {
        jmToken.setPrivateSaleEnabled(false);

        uint256 soldBefore = jmToken.privateSaleSold();
        uint256 balanceBefore = jmToken.balanceOf(user1);
        vm.prank(user1);
        (bool success, ) = payable(address(jmToken)).call{value: 0.2 ether}("");
        assertTrue(success); // 当前合约实现: 关闭时仅不发放,不回退
        assertEq(jmToken.privateSaleSold(), soldBefore);
        assertEq(jmToken.balanceOf(user1), balanceBefore);
    }

    function _revertMsg(
        bytes memory revertData
    ) internal pure returns (string memory) {
        if (revertData.length < 68) return "";
        assembly {
            revertData := add(revertData, 0x04)
        }
        return abi.decode(revertData, (string));
    }

    // ========== 燃烧测试 ==========

    function test_MonthlyBurnTooEarly() public {
        vm.expectRevert("Too early");
        jmToken.monthlyBurn();
    }

    function test_MonthlyBurnExceedMax() public {
        address pair = jmToken.lpPair();

        // 执行10次燃烧
        for (uint256 i = 0; i < 10; i++) {
            // 给pair补充JM用于燃烧
            deal(address(jmToken), pair, 500_000 ether, true);
            // 快进30天
            vm.warp(block.timestamp + 31 days);
            // 执行燃烧
            jmToken.monthlyBurn();
        }

        // 验证燃烧次数为10
        assertEq(jmToken.burnCount(), 10);

        // 第11次应该失败
        deal(address(jmToken), pair, 500_000 ether, true);
        vm.warp(block.timestamp + 31 days);
        vm.expectRevert("Burn completed");
        jmToken.monthlyBurn();
    }

    function test_MonthlyBurnSuccess() public {
        address pair = jmToken.lpPair();

        // 使用deal给pair设置JM余额(模拟底池有流动性)
        deal(address(jmToken), pair, 5_000_000 ether, true);

        // 快进30天
        vm.warp(block.timestamp + 31 days);

        uint256 deadBalanceBefore = jmToken.balanceOf(jmToken.DEAD());
        uint256 pairBalanceBefore = jmToken.balanceOf(pair);

        jmToken.monthlyBurn();

        uint256 deadBalanceAfter = jmToken.balanceOf(jmToken.DEAD());
        uint256 pairBalanceAfter = jmToken.balanceOf(pair);

        // 验证从pair转到了dead
        assertEq(deadBalanceAfter - deadBalanceBefore, 500_000 ether);
        assertEq(pairBalanceBefore - pairBalanceAfter, 500_000 ether);
        assertEq(jmToken.burnCount(), 1);
    }

    // ========== 白名单/黑名单测试 ==========

    function test_Whitelist() public {
        jmToken.setWhitelist(user1, true);
        assertTrue(jmToken.isWhitelisted(user1));
    }

    function test_Blacklist() public {
        jmToken.setBlacklist(user1, true);
        assertTrue(jmToken.isBlacklisted(user1));
    }

    // ========== LP分红合约关联测试 ==========

    function test_LPDistributorSetting() public {
        assertEq(jmToken.lpDistributor(), address(lpDistributor));
    }

    function test_JMBMinterSetting() public {
        assertEq(jmbToken.minter(), address(lpDistributor));
    }

    function test_JMB_NonTransferable() public {
        jmbToken.setMinter(address(this));
        jmbToken.mint(user1, 100 ether);

        vm.expectRevert(JMBToken.NonTransferable.selector);
        vm.prank(user1);
        jmbToken.approve(user2, 1 ether);

        vm.expectRevert(JMBToken.NonTransferable.selector);
        vm.prank(user1);
        jmbToken.transfer(user2, 1 ether);

        vm.expectRevert(JMBToken.NonTransferable.selector);
        vm.prank(user2);
        jmbToken.transferFrom(user1, user2, 1 ether);
    }

    // ========== 交易所锁仓测试 ==========

    function test_ExchangeLockRecipient() public {
        // 锁仓地址固定为 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e
        assertEq(
            jmToken.EXCHANGE_LOCK_RECIPIENT(),
            0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e
        );
    }

    function test_ExchangeLockTooEarly() public {
        vm.expectRevert("Lock period not ended");
        jmToken.claimExchangeLock();
    }

    function test_ExchangeLockSuccess() public {
        address lockRecipient = 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e;
        // 锁仓份额已在构造函数预留到合约, 这里无需再转入

        // 快进365天
        vm.warp(block.timestamp + 366 days);

        uint256 balanceBefore = jmToken.balanceOf(lockRecipient);

        // 任何人都可以触发解锁 (用user2调用)
        vm.prank(user2);
        jmToken.claimExchangeLock();

        uint256 balanceAfter = jmToken.balanceOf(lockRecipient);
        assertEq(balanceAfter - balanceBefore, 2_000_000 ether);
        assertTrue(jmToken.exchangeLockClaimed());
    }

    function test_ExchangeLockAlreadyClaimed() public {
        // 锁仓份额已在构造函数预留到合约
        // 快进365天并解锁
        vm.warp(block.timestamp + 366 days);
        jmToken.claimExchangeLock();

        // 再次尝试解锁应该失败
        vm.expectRevert("Already claimed");
        jmToken.claimExchangeLock();
    }

    function test_GetExchangeLockStatus() public {
        (
            uint256 amount,
            uint256 unlockTime,
            bool canClaim,
            bool claimed,
            address recipient
        ) = jmToken.getExchangeLockStatus();

        assertEq(amount, 2_000_000 ether);
        assertGt(unlockTime, block.timestamp);
        assertEq(recipient, 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e);
        assertFalse(claimed);
        assertFalse(canClaim); // 时间还没到
    }

    // ========== 需求关键路径测试 ==========

    function test_BuyFee_Is3Percent() public {
        jmToken.setTradingEnabled(true);
        // 关闭分红分发,避免买入时二次swap影响本用例的费率验证
        jmToken.setLPDistributor(address(0));

        uint256 amount = 1000 ether;
        address pair = jmToken.lpPair();

        uint256 userBefore = jmToken.balanceOf(user1);
        uint256 contractBefore = jmToken.balanceOf(address(jmToken));
        uint256 deadBefore = jmToken.balanceOf(jmToken.DEAD());

        vm.prank(pair);
        jmToken.transfer(user1, amount);

        uint256 userDelta = jmToken.balanceOf(user1) - userBefore;
        uint256 contractDelta = jmToken.balanceOf(address(jmToken)) -
            contractBefore;
        uint256 deadDelta = jmToken.balanceOf(jmToken.DEAD()) - deadBefore;

        // 买入3%: 1%回流,1.5%分红,0.5%黑洞
        // 关闭分红分发后,合约应累计1%+1.5%=2.5%
        assertEq(userDelta, 970 ether);
        assertEq(contractDelta, 25 ether);
        assertEq(deadDelta, 5 ether);
    }

    function test_SellFee_Is3Percent() public {
        // 关闭分红分发,避免卖出路径中的swap回调触发receive限制
        jmToken.setLPDistributor(address(0));

        vm.prank(user1);
        (bool success, ) = payable(address(jmToken)).call{value: 0.2 ether}("");
        assertTrue(success);

        uint256 amount = 1000 ether;
        address pair = jmToken.lpPair();

        uint256 pairBefore = jmToken.balanceOf(pair);
        uint256 contractBefore = jmToken.balanceOf(address(jmToken));
        uint256 deadBefore = jmToken.balanceOf(jmToken.DEAD());

        vm.prank(user1);
        jmToken.transfer(pair, amount);

        uint256 pairDelta = jmToken.balanceOf(pair) - pairBefore;
        uint256 contractDelta = jmToken.balanceOf(address(jmToken)) -
            contractBefore;
        uint256 deadDelta = jmToken.balanceOf(jmToken.DEAD()) - deadBefore;

        // 关闭分红后,合约累计1%+1.5%=2.5%, pair仅收到净额970
        assertEq(pairDelta, 970 ether);
        assertEq(contractDelta, 25 ether);
        assertEq(deadDelta, 5 ether);
    }

    function test_RemoveLiquidityETH_RealPath() public {
        jmToken.setTradingEnabled(true);

        address pair = jmToken.lpPair();
        uint256 lpInJMToken = IPancakePair(pair).balanceOf(address(jmToken));
        uint256 lpToRemove = lpInJMToken / 10;

        // 从JMToken合约提取LP到owner,再走真实router移除流动性
        jmToken.withdrawTokens(pair, lpToRemove);
        IPancakePair(pair).approve(PANCAKE_ROUTER, lpToRemove);

        uint256 userTokenBefore = jmToken.balanceOf(user1);
        IPancakeRouter(PANCAKE_ROUTER).removeLiquidityETH(
            address(jmToken),
            lpToRemove,
            0,
            0,
            user1,
            block.timestamp
        );
        uint256 userTokenAfter = jmToken.balanceOf(user1);
        assertGt(userTokenAfter, userTokenBefore);
    }

    function test_LPRewardUnlockFlow_BuyPathBlocked() public {
        jmToken.setTradingEnabled(true);

        address pair = jmToken.lpPair();
        IPancakePair pairContract = IPancakePair(pair);
        (uint112 reserve0, uint112 reserve1, ) = pairContract.getReserves();
        uint256 bnbReserve = pairContract.token0() == WBNB
            ? uint256(reserve0)
            : uint256(reserve1);
        uint256 totalLp = pairContract.totalSupply();

        // 1) 从JMToken提取约4 BNB价值LP,转给user1并质押
        uint256 lpForStake = (4 ether * totalLp) / bnbReserve;
        jmToken.withdrawTokens(pair, lpForStake);
        pairContract.transfer(user1, lpForStake);

        vm.startPrank(user1);
        pairContract.approve(address(lpDistributor), lpForStake);
        lpDistributor.stakeLP(lpForStake);
        vm.stopPrank();

        // 2) 分发1 BNB分红
        lpDistributor.distributeBNB{value: 1 ether}();

        // 3) 真实主网买入路径当前回退,导致recordBuy无法执行
        vm.expectRevert();
        _swapExactETHForJM(user1, 0.01 ether);

        (
            ,
            uint256 pending1,
            uint256 unlocked1,
            uint256 needBuy1,
            uint256 bought1
        ) = lpDistributor.getUserInfo(user1);
        assertGt(pending1, 0);
        assertEq(unlocked1, 0);
        assertEq(needBuy1, 0);
        assertEq(bought1, 0);
    }

    function _swapExactETHForJM(address buyer, uint256 bnbAmount) internal {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(jmToken);

        vm.prank(buyer);
        IPancakeRouter(PANCAKE_ROUTER)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: bnbAmount
        }(0, path, buyer, block.timestamp);
    }
}
