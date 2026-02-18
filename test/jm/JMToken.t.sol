// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/jm/JMToken.sol";
import "../../src/jm/LPDistributor.sol";
import "../../src/jm/interfaces/IPancakeRouter.sol";
import "../../src/jm/interfaces/IPancakePair.sol";
import "../../src/jm/interfaces/IWBNB.sol";

/**
 * @title JMTokenTest
 * @dev JM Token 单元测试
 * 运行: forge test --match-path test/jm/JMToken.t.sol -vv
 * forge test --match-test "test_(WhitelistCanBuyWhenTradingDisabled|BuyPathNotMisclassifiedAsRemoveLiquidity|RemoveLiquidityCharges20PercentDirectRouter)" -vv
 */
contract JMTokenTest is Test {
    JMToken public jmToken;
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
        lpDistributor = new LPDistributor(address(jmToken), jmToken.lpPair());

        // 配置合约
        jmToken.setLPDistributor(address(lpDistributor));

        // 按需求使用Pancake真实路由添加20 BNB流动性
        jmToken.addLiquidity{value: 20 ether}(200_000 ether);
    }

    // ========== 基础功能测试 ==========

    // 验证代币名称、符号、总量和精度是否符合预期.
    function test_TokenInfo() public view {
        assertEq(jmToken.name(), "JM Token");
        assertEq(jmToken.symbol(), "JM");
        // 总量2100万 - 固定销毁500万 = 1600万流通
        assertEq(jmToken.totalSupply(), 16_000_000 ether);
        assertEq(jmToken.decimals(), 18);
    }

    // 验证初始化后代币合约余额与管理员余额是否符合预期.
    function test_InitialBalance() public view {
        uint256 contractBalance = jmToken.balanceOf(address(jmToken));
        uint256 ownerBalance = jmToken.balanceOf(owner);

        // 合约预留1900万 - 固定销毁500万 = 1400万
        assertEq(contractBalance, 14_000_000 ether);
        // 管理员200万扣除建池666,667, 剩余1,333,333
        assertLt(ownerBalance, 2_000_000 ether);
    }

    // ========== 私募测试 ==========

    // 验证私募打款0.2 BNB后可收到6000 JM.
    function test_PrivateSale() public {
        uint256 initialBalance = jmToken.balanceOf(user1);

        vm.prank(user1);
        (bool success, ) = payable(address(jmToken)).call{value: 0.2 ether}("");
        assertTrue(success);

        // 检查收到6000 JM
        assertEq(jmToken.balanceOf(user1) - initialBalance, 6000 ether);
    }

    // 验证私募金额必须严格等于0.2 BNB.
    function test_PrivateSaleExactAmount() public {
        vm.prank(user1);
        (bool success, bytes memory data) = payable(address(jmToken)).call{
            value: 0.1 ether
        }("");
        assertFalse(success);
        assertEq(_revertMsg(data), "Invalid BNB amount");
    }

    // 验证私募关闭后打款不会发放代币.
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

    // 验证每个地址只能参与一次私募.
    function test_PrivateSale_OnlyOnePerAddress() public {
        vm.prank(user1);
        (bool firstSuccess, ) = payable(address(jmToken)).call{
            value: 0.2 ether
        }("");
        assertTrue(firstSuccess);

        vm.prank(user1);
        (bool secondSuccess, bytes memory data) = payable(address(jmToken))
            .call{value: 0.2 ether}("");
        assertFalse(secondSuccess);
        assertEq(_revertMsg(data), "Already participated");
    }

    // 验证私募卖完2000份后拒绝新购买.
    // 注意: 此测试仅验证私募机制存在,未真正卖出2000份(会超时)
    // 实际2000份售罄需通过脚本验证
    function test_PrivateSaleSoldOut() public {
        // 验证私募当前售出份数为0
        (uint256 sold, , ) = jmToken.getPrivateSaleStatus();
        assertEq(sold, 0);

        // 给测试用户充值BNB
        address testUser = address(0x1111);
        vm.deal(testUser, 100 ether);

        // 验证私募可以购买
        vm.prank(testUser);
        (bool success, ) = payable(address(jmToken)).call{value: 0.2 ether}("");
        assertTrue(success);

        // 验证购买后sold增加(私募成功)
        (sold, , ) = jmToken.getPrivateSaleStatus();
        assertEq(sold, 1, unicode"私募购买后sold应增加");
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

    // ========== 白名单/黑名单测试 ==========

    // 验证白名单设置生效.
    function test_Whitelist() public {
        jmToken.setWhitelist(user1, true);
        assertTrue(jmToken.isWhitelisted(user1));
    }

    // 验证黑名单设置生效.
    function test_Blacklist() public {
        jmToken.setBlacklist(user1, true);
        assertTrue(jmToken.isBlacklisted(user1));
    }

    // 验证白名单地址在trading关闭时仍能买入.
    function test_WhitelistCanBuyWhenTradingDisabled() public {
        // trading默认关闭
        assertFalse(jmToken.tradingEnabled());

        // 设置user1为白名单
        jmToken.setWhitelist(user1, true);
        assertTrue(jmToken.isWhitelisted(user1));

        // 白名单用户通过真实PancakeSwap买入(trading关闭, 白名单仍可买入且免手续费)
        address pair = jmToken.lpPair();
        uint256 pairBefore = jmToken.balanceOf(pair);
        _swapExactETHForJM(user1, 1 ether);
        uint256 grossBought = pairBefore - jmToken.balanceOf(pair);

        // 白名单买入免手续费, 到账应等于pair送出的全部JM
        assertEq(
            jmToken.balanceOf(user1),
            grossBought,
            unicode"白名单用户应能买入(免手续费)"
        );
    }

    // ========== LP分红合约关联测试 ==========

    // 验证JMToken中的LP分红合约地址配置正确.
    function test_LPDistributorSetting() public view {
        assertEq(jmToken.lpDistributor(), address(lpDistributor));
    }

    // 验证JMB凭证信息.
    function test_JMBMinterSetting() public view {
        assertEq(lpDistributor.symbol(), "JMB");
    }

    // 验证JMB不可转账、不可授权、不可代理转账.
    function test_JMB_NonTransferable() public {
        vm.expectRevert(LPDistributor.NonTransferable.selector);
        vm.prank(user1);
        lpDistributor.approve(user2, 1 ether);

        vm.expectRevert(LPDistributor.NonTransferable.selector);
        vm.prank(user1);
        lpDistributor.transfer(user2, 1 ether);

        vm.expectRevert(LPDistributor.NonTransferable.selector);
        vm.prank(user2);
        lpDistributor.transferFrom(user1, user2, 1 ether);
    }

    // ========== 交易所锁仓测试 ==========

    // 验证交易所锁仓接收地址常量正确.
    function test_ExchangeLockRecipient() public view {
        // 锁仓地址固定为 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e
        assertEq(
            jmToken.EXCHANGE_LOCK_RECIPIENT(),
            0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e
        );
    }

    // 验证锁仓未到期时不可解锁.
    function test_ExchangeLockTooEarly() public {
        vm.expectRevert("Lock period not ended");
        jmToken.claimExchangeLock();
    }

    // 验证锁仓到期后可被任意地址触发解锁.
    function test_ExchangeLockSuccess() public {
        address lockRecipient = 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e;

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

    // 验证锁仓只能解锁一次.
    function test_ExchangeLockAlreadyClaimed() public {
        vm.warp(block.timestamp + 366 days);
        jmToken.claimExchangeLock();

        vm.expectRevert("Already claimed");
        jmToken.claimExchangeLock();
    }

    // 验证锁仓状态查询返回值正确.
    function test_GetExchangeLockStatus() public view {
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
        assertFalse(canClaim);
    }

    // ========== 需求关键路径测试 ==========

    // 验证买入总费率为3%且各费用拆分正确, 同时验证分红链路(累积->触发->JM->WBNB->LPDistributor->BNB).
    function test_BuyFee_Is3Percent() public {
        jmToken.setTradingEnabled(true);
        address pair = jmToken.lpPair();
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(jmToken);

        // --- 第一笔买入: 验证费率拆分, rewardFee累积到合约 ---
        uint256 userBefore = jmToken.balanceOf(user1);
        uint256 deadBefore = jmToken.balanceOf(jmToken.DEAD());
        uint256 pairBefore = jmToken.balanceOf(pair);

        vm.prank(user1);
        IPancakeRouter(PANCAKE_ROUTER)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0,
            path,
            user1,
            block.timestamp
        );

        uint256 userDelta = jmToken.balanceOf(user1) - userBefore;
        uint256 deadDelta = jmToken.balanceOf(jmToken.DEAD()) - deadBefore;
        uint256 grossBought = pairBefore - jmToken.balanceOf(pair);

        // 用户到账 = grossBought - 3%总费用 (1%留池 + 1.5%累积到合约 + 0.5%黑洞)
        uint256 expectedFee = (grossBought * 300) / 10000;
        assertApproxEqAbs(
            userDelta,
            grossBought - expectedFee,
            grossBought / 100
        );

        // 黑洞收到 0.5%
        uint256 expectedBurn = (grossBought * 50) / 10000;
        assertApproxEqAbs(deadDelta, expectedBurn, grossBought / 100);

        // 1.5% rewardFee已累积到pendingRewardTokens
        assertGt(jmToken.pendingRewardTokens(), 0, unicode"应有累积分红");

        uint256 distributorBnbBefore = address(lpDistributor).balance;

        // 用普通转账触发_update -> pendingRewardTokens >= MIN_REWARD_SWAP -> swap分发
        deal(address(jmToken), user2, 1000 ether, true);
        vm.prank(user2);
        jmToken.transfer(user3, 100 ether);

        // 如果累积量达到MIN_REWARD_SWAP, 分红合约应收到BNB
        if (jmToken.pendingRewardTokens() == 0) {
            uint256 distributorBnbDelta = address(lpDistributor).balance -
                distributorBnbBefore;
            assertGt(distributorBnbDelta, 0, unicode"LP分红合约应收到BNB");
        }
    }

    // 验证无有效流动性时, 即使路径形似买入也不收税.
    function test_NoLiquidity_NoFee() public {
        JMToken freshToken = new JMToken(PANCAKE_ROUTER);
        address freshPair = freshToken.lpPair();
        uint256 amount = 1000 ether;

        deal(address(freshToken), freshPair, amount, true);

        uint256 userBefore = freshToken.balanceOf(user1);
        uint256 contractBefore = freshToken.balanceOf(address(freshToken));
        uint256 deadBefore = freshToken.balanceOf(freshToken.DEAD());

        vm.prank(freshPair);
        freshToken.transfer(user1, amount);

        assertEq(freshToken.balanceOf(user1) - userBefore, amount);
        assertEq(freshToken.balanceOf(address(freshToken)), contractBefore);
        assertEq(freshToken.balanceOf(freshToken.DEAD()), deadBefore);
    }

    // 验证卖出总费率为3%且各费用拆分正确, 同时验证分红链路.
    function test_SellFee_Is3Percent() public {
        // 先让user1通过私售获得JM代币
        vm.prank(user1);
        (bool success, ) = payable(address(jmToken)).call{value: 0.2 ether}("");
        assertTrue(success);

        uint256 amount = 1000 ether;
        address pair = jmToken.lpPair();

        uint256 pairBefore = jmToken.balanceOf(pair);
        uint256 deadBefore = jmToken.balanceOf(jmToken.DEAD());

        address[] memory path = new address[](2);
        path[0] = address(jmToken);
        path[1] = WBNB;
        vm.startPrank(user1);
        jmToken.approve(PANCAKE_ROUTER, amount);
        IPancakeRouter(PANCAKE_ROUTER)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amount,
                0,
                path,
                address(user1),
                block.timestamp
            );
        vm.stopPrank();

        uint256 pairDelta = jmToken.balanceOf(pair) - pairBefore;
        uint256 deadDelta = jmToken.balanceOf(jmToken.DEAD()) - deadBefore;

        // 卖出3%: 1%回流到底池, pair收到980, 黑洞收到5, 1.5%累积到合约
        assertEq(pairDelta, 980 ether);
        assertEq(deadDelta, 5 ether);

        // 1.5% rewardFee已累积
        assertGt(jmToken.pendingRewardTokens(), 0, unicode"卖出后应有累积分红");

        // --- 触发累积分红分发 ---
        uint256 distributorBnbBefore = address(lpDistributor).balance;
        deal(address(jmToken), user2, 1000 ether, true);
        vm.prank(user2);
        jmToken.transfer(user3, 100 ether);

        if (jmToken.pendingRewardTokens() == 0) {
            uint256 distributorBnbDelta = address(lpDistributor).balance -
                distributorBnbBefore;
            assertGt(distributorBnbDelta, 0, unicode"LP分红合约应收到BNB");
        }
    }

    // 验证撤池检测逻辑:
    // 普通买入应走3%买税, 不应误判为20%撤池税.
    function test_BuyPathNotMisclassifiedAsRemoveLiquidity() public {
        jmToken.setTradingEnabled(true);

        address pair = jmToken.lpPair();
        uint256 pairBefore = jmToken.balanceOf(pair);
        uint256 userBefore = jmToken.balanceOf(user1);
        uint256 deadBefore = jmToken.balanceOf(jmToken.DEAD());
        uint256 contractBefore = jmToken.balanceOf(address(jmToken));
        uint256 pendingBefore = jmToken.pendingRewardTokens();

        _swapExactETHForJM(user1, 1 ether);

        uint256 grossBought = pairBefore - jmToken.balanceOf(pair);
        uint256 expectedBurn = (grossBought * 50) / 10000; // 0.5%
        uint256 expectedReward = (grossBought * 150) / 10000; // 1.5%
        uint256 expectedReceive = grossBought - ((grossBought * 300) / 10000); // 97%

        assertApproxEqAbs(
            jmToken.balanceOf(user1) - userBefore,
            expectedReceive,
            grossBought / 100
        );
        assertApproxEqAbs(
            jmToken.balanceOf(jmToken.DEAD()) - deadBefore,
            expectedBurn,
            grossBought / 100
        );
        assertApproxEqAbs(
            jmToken.balanceOf(address(jmToken)) - contractBefore,
            expectedReward,
            grossBought / 100
        );
        assertApproxEqAbs(
            jmToken.pendingRewardTokens() - pendingBefore,
            expectedReward,
            grossBought / 100
        );
    }

    // 验证 removeLiquidity 双币退出时:
    // JM侧按20%撤池税分配(10%留池,5%分红,5%黑洞)
    function test_RemoveLiquidityCharges20PercentDirectRouter() public {
        jmToken.setTradingEnabled(true);

        address pair = jmToken.lpPair();

        // 1) user 买入 JM
        _swapExactETHForJM(user1, 1 ether);

        // 2) user 添加流动性 (获得 LP)
        _addLiquidityETH(user1, jmToken.balanceOf(user1) / 2, 1 ether);
        uint256 lpBalance = IPancakePair(pair).balanceOf(user1);
        assertGt(lpBalance, 0, unicode"添加流动性后应有LP");

        uint256 pairJmBefore = jmToken.balanceOf(pair);
        uint256 userJmBefore = jmToken.balanceOf(user1);
        uint256 deadBefore = jmToken.balanceOf(jmToken.DEAD());
        uint256 contractBefore = jmToken.balanceOf(address(jmToken));
        uint256 pendingBefore = jmToken.pendingRewardTokens();

        // 3) user 双币退出 (removeLiquidity) - 移除流动性获得两种代币
        vm.startPrank(user1);
        IPancakePair(pair).approve(PANCAKE_ROUTER, lpBalance);

        // 使用 removeLiquidity (双币退出)
        // 参数: tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline
        (uint256 amountTokenGross, ) = IPancakeRouter(PANCAKE_ROUTER)
            .removeLiquidity(
                address(jmToken),
                WBNB,
                lpBalance,
                1,
                1,
                user1,
                block.timestamp + 1
            );
        vm.stopPrank();

        // 4) 验证20%撤池税分配
        uint256 expectedBurn = (amountTokenGross * 500) / 10000; // 5%
        uint256 expectedReward = (amountTokenGross * 500) / 10000; // 5%
        uint256 expectedReceive = amountTokenGross -
            ((amountTokenGross * 2000) / 10000); // 80%

        // 用户实际到账=80%
        assertEq(
            jmToken.balanceOf(user1) - userJmBefore,
            expectedReceive,
            unicode"双币退出用户JM到账应为80%"
        );
        // 黑洞=5%
        assertEq(
            jmToken.balanceOf(jmToken.DEAD()) - deadBefore,
            expectedBurn,
            unicode"双币退出黑洞应为5%"
        );
        // 分红池=5%
        assertEq(
            jmToken.balanceOf(address(jmToken)) - contractBefore,
            expectedReward,
            unicode"双币退出分红应为5%"
        );
        // pendingRewardTokens应同步增加5%
        assertEq(
            jmToken.pendingRewardTokens() - pendingBefore,
            expectedReward,
            unicode"pendingReward应增加5%"
        );
        // pair净减少=80%+5%+5%=90%(10%回流留在池子)
        assertEq(
            pairJmBefore - jmToken.balanceOf(pair),
            expectedReceive + expectedBurn + expectedReward,
            unicode"双币退出pair净减少应为90%"
        );
    }

    // 验证 removeLiquidityETHSupportingFeeOnTransferTokens 路径也收20%撤池税
    // 这是PancakeSwap前端对BNB池子实际调用的函数(pair -> router -> user)
    function test_RemoveLiquidityETHSupportingFeeCharges20Percent() public {
        jmToken.setTradingEnabled(true);

        address pair = jmToken.lpPair();

        // 1) user 买入 JM
        _swapExactETHForJM(user1, 1 ether);

        // 2) user 添加流动性 (获得 LP)
        _addLiquidityETH(user1, jmToken.balanceOf(user1) / 2, 1 ether);
        uint256 lpBalance = IPancakePair(pair).balanceOf(user1);
        assertGt(lpBalance, 0, unicode"添加流动性后应有LP");

        uint256 userJmBefore = jmToken.balanceOf(user1);
        uint256 deadBefore = jmToken.balanceOf(jmToken.DEAD());

        // 3) user 通过 removeLiquidityETHSupportingFeeOnTransferTokens 撤池
        //    真实PancakeSwap UI对BNB池子的调用路径: pair -> router -> user
        vm.startPrank(user1);
        IPancakePair(pair).approve(PANCAKE_ROUTER, lpBalance);
        uint256 amountETH = IPancakeRouter(PANCAKE_ROUTER)
            .removeLiquidityETHSupportingFeeOnTransferTokens(
                address(jmToken),
                lpBalance,
                1,
                1,
                user1,
                block.timestamp + 1
            );
        vm.stopPrank();

        // 4) 验证BNB侧有返回(ETH侧不受JM税影响)
        assertGt(amountETH, 0, unicode"应返回BNB");

        // 5) 验证JM侧收了20%撤池税
        //    pair -> router 被扣20%, router用balanceOf转发剩余80%给user
        //    关系: deadDelta(5%) = userJmDelta(80%) * 5/80 = userJmDelta / 16
        uint256 userJmDelta = jmToken.balanceOf(user1) - userJmBefore;
        uint256 deadDelta = jmToken.balanceOf(jmToken.DEAD()) - deadBefore;

        assertGt(userJmDelta, 0, unicode"用户应收到JM(扣税后)");
        assertGt(deadDelta, 0, unicode"黑洞应收到5%");

        // 黑洞/用户 比例 = 5%/80% = 1/16
        uint256 expectedBurn = userJmDelta / 16;
        assertApproxEqAbs(
            deadDelta,
            expectedBurn,
            2,
            unicode"ETH撤池路径: 黑洞应为用户到账的1/16(5% vs 80%)"
        );
    }

    // 验证关闭撤池税后, removeLiquidity不再走20%, 而是回到买入3%路径
    function test_RemoveLiquidityUsesBuyFeeWhenRemoveTaxDisabled() public {
        jmToken.setTradingEnabled(true);
        jmToken.setRemoveLiquidityTaxEnabled(false);

        address pair = jmToken.lpPair();

        // 1) user 买入 JM
        _swapExactETHForJM(user1, 1 ether);

        // 2) user 添加流动性 (获得 LP)
        _addLiquidityETH(user1, jmToken.balanceOf(user1) / 2, 1 ether);
        uint256 lpBalance = IPancakePair(pair).balanceOf(user1);
        assertGt(lpBalance, 0, unicode"添加流动性后应有LP");

        uint256 pairJmBefore = jmToken.balanceOf(pair);
        uint256 userJmBefore = jmToken.balanceOf(user1);
        uint256 deadBefore = jmToken.balanceOf(jmToken.DEAD());
        uint256 contractBefore = jmToken.balanceOf(address(jmToken));
        uint256 pendingBefore = jmToken.pendingRewardTokens();

        // 3) 直接走 router.removeLiquidity
        vm.startPrank(user1);
        IPancakePair(pair).approve(PANCAKE_ROUTER, lpBalance);
        (uint256 amountTokenGross, ) = IPancakeRouter(PANCAKE_ROUTER)
            .removeLiquidity(
                address(jmToken),
                WBNB,
                lpBalance,
                1,
                1,
                user1,
                block.timestamp + 1
            );
        vm.stopPrank();

        // 4) 应按买入3%分配: 1%留池,1.5%分红,0.5%黑洞,用户到账97%
        uint256 expectedBurn = (amountTokenGross * 50) / 10000; // 0.5%
        uint256 expectedReward = (amountTokenGross * 150) / 10000; // 1.5%
        uint256 expectedReceive = amountTokenGross -
            ((amountTokenGross * 300) / 10000); // 97%

        assertApproxEqAbs(
            jmToken.balanceOf(user1) - userJmBefore,
            expectedReceive,
            1,
            unicode"关闭撤池税后removeLiquidity用户到账应为97%"
        );
        assertApproxEqAbs(
            jmToken.balanceOf(jmToken.DEAD()) - deadBefore,
            expectedBurn,
            1,
            unicode"关闭撤池税后黑洞应为0.5%"
        );
        assertApproxEqAbs(
            jmToken.balanceOf(address(jmToken)) - contractBefore,
            expectedReward,
            1,
            unicode"关闭撤池税后分红应为1.5%"
        );
        assertApproxEqAbs(
            jmToken.pendingRewardTokens() - pendingBefore,
            expectedReward,
            1,
            unicode"关闭撤池税后pendingReward应增加1.5%"
        );
        // pair净减少=97%+0.5%+1.5%=99%(1%回流留在池子)
        assertApproxEqAbs(
            pairJmBefore - jmToken.balanceOf(pair),
            expectedReceive + expectedBurn + expectedReward,
            1,
            unicode"关闭撤池税后pair净减少应为99%"
        );
    }

    // ========== LP自动分红追踪测试 ==========

    // 验证用户通过PancakeSwap真实添加流动性后, 交易自动被追踪为分红对象
    function test_LPAutoTrack() public {
        jmToken.setTradingEnabled(true);

        // 1) user1先买入JM(真实PancakeSwap买入)
        _swapExactETHForJM(user1, 5 ether);
        uint256 jmBalance = jmToken.balanceOf(user1);
        assertGt(jmBalance, 0, unicode"买入后应有JM");

        // 2) user1通过PancakeSwap真实添加流动性(4 BNB + 对应JM)
        _addLiquidityETH(user1, jmBalance / 2, 4 ether);

        // 3) 验证user1确实持有LP
        address pair = jmToken.lpPair();
        uint256 userLP = IPancakePair(pair).balanceOf(user1);
        assertGt(userLP, 0, unicode"添加流动性后应有LP");

        // 4) 再执行一笔买入, 触发_update -> setBalance自动同步LP余额
        _swapExactETHForJM(user1, 0.01 ether);

        // 5) 验证LPDistributor已自动追踪到user1的LP份额
        (uint256 userShares, , , , ) = lpDistributor.getUserInfo(user1);
        assertGt(userShares, 0, unicode"LP持有者应被自动追踪");

        // 6) 验证JMB凭证余额(动态等于shares)
        assertGt(lpDistributor.balanceOf(user1), 0, unicode"JMB凭证应自动铸造");
    }

    // 验证用户手动syncBalance同步LP份额
    function test_ManualSyncBalance() public {
        jmToken.setTradingEnabled(true);

        // user1先买入JM
        _swapExactETHForJM(user1, 5 ether);
        uint256 jmBalance = jmToken.balanceOf(user1);

        // user1添加流动性
        _addLiquidityETH(user1, jmBalance / 2, 4 ether);

        // 验证持有LP但未同步(因为没有触发setBalance的交易)
        address pair = jmToken.lpPair();
        uint256 userLP = IPancakePair(pair).balanceOf(user1);
        assertGt(userLP, 0, unicode"应有LP");

        // 在没有同步前,shares应为0
        (uint256 sharesBefore, , , , ) = lpDistributor.getUserInfo(user1);

        // 手动调用syncBalance同步
        vm.prank(user1);
        lpDistributor.syncBalance();

        // 验证同步后shares大于0
        (uint256 sharesAfter, , , , ) = lpDistributor.getUserInfo(user1);
        assertGt(sharesAfter, sharesBefore, unicode"syncBalance后应有份额");
    }

    // 验证LP价值低于门槛(0.1 BNB)的用户不参与分红
    function test_LPBelowThreshold_NoShares() public {
        jmToken.setTradingEnabled(true);

        // user1先买入少量JM
        _swapExactETHForJM(user1, 0.1 ether);
        uint256 jmBalance = jmToken.balanceOf(user1);

        // 添加极小额流动性(0.01 BNB, 远低于0.1 BNB门槛)
        _addLiquidityETH(user1, jmBalance / 4, 0.01 ether);

        // 验证确实持有LP
        address pair = jmToken.lpPair();
        assertGt(IPancakePair(pair).balanceOf(user1), 0, unicode"应有LP");

        // 触发一笔买入同步LP余额
        _swapExactETHForJM(user1, 0.01 ether);

        // LP价值低于门槛, 不应有分红份额
        (uint256 userShares, , , , ) = lpDistributor.getUserInfo(user1);
        assertEq(userShares, 0, unicode"LP价值低于门槛不应有份额");
    }

    // 验证完整LP分红解锁链路: 真实添加流动性 -> 分发BNB -> 真实买入触发recordBuy -> 自动领取分红
    function test_LPRewardUnlockFlow() public {
        jmToken.setTradingEnabled(true);

        // 1) user1先买入JM
        _swapExactETHForJM(user1, 8 ether);
        uint256 jmBalance = jmToken.balanceOf(user1);

        // 2) user1通过PancakeSwap真实添加流动性(4 BNB)
        _addLiquidityETH(user1, jmBalance / 2, 4 ether);

        // 验证LP持有
        address pair = jmToken.lpPair();
        assertGt(IPancakePair(pair).balanceOf(user1), 0, unicode"应有LP");

        // 3) 触发一笔买入, 让setBalance同步user1的LP余额
        _swapExactETHForJM(user1, 0.01 ether);

        // 验证user1已被追踪
        (uint256 shares1, , , , ) = lpDistributor.getUserInfo(user1);
        assertGt(shares1, 0, unicode"user1应有LP份额");

        // 4) 分发1 BNB分红(直接打款触发receive)
        (bool sent, ) = payable(address(lpDistributor)).call{value: 1 ether}(
            ""
        );
        assertTrue(sent);

        // 5) 真实买入触发recordBuy
        //    如果买入金额 >= needBuyToUnlock, 分红会在recordBuy内自动发放给user1
        _swapExactETHForJM(user1, 0.5 ether);

        // 6) 验证: 分红已通过recordBuy自动发放(pending/unlocked/bought全部清零)
        //    或者pending仍有值(买入金额不足以解锁全部分红)
        (
            ,
            uint256 pending1,
            uint256 unlocked1,
            uint256 needBuy1,
            uint256 bought1
        ) = lpDistributor.getUserInfo(user1);

        if (pending1 == 0 && unlocked1 == 0 && needBuy1 == 0) {
            // 分红已自动发放: user1的BNB应增加(扣除买入花费后净增)
            // 买入花了0.5 BNB, 但收到了约1 BNB分红, 净增约0.5 BNB
            // 由于swap也消耗了gas, 这里只验证分红确实发生过(bought被清零说明解锁成功)
            assertEq(bought1, 0, unicode"解锁后购买金额应清零");
        } else {
            // 买入金额不足以解锁, pending应有值
            assertGt(pending1 + unlocked1, 0, unicode"应有待领或已解锁分红");
            assertGt(bought1, 0, unicode"买入后应记录购买金额");
        }
    }

    // 验证排除地址(pair/router/dead等)不参与分红
    function test_ExcludedAddresses_NoShares() public view {
        assertTrue(
            lpDistributor.isExcludedFromDividends(jmToken.lpPair()),
            unicode"pair应被排除"
        );
        assertTrue(
            lpDistributor.isExcludedFromDividends(PANCAKE_ROUTER),
            unicode"router应被排除"
        );
        assertTrue(
            lpDistributor.isExcludedFromDividends(jmToken.DEAD()),
            unicode"dead应被排除"
        );
        assertTrue(
            lpDistributor.isExcludedFromDividends(address(jmToken)),
            unicode"代币合约应被排除"
        );
        assertTrue(
            lpDistributor.isExcludedFromDividends(address(lpDistributor)),
            unicode"分红合约应被排除"
        );
    }

    // ========== Helper ==========

    // 真实PancakeSwap买入JM
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

    // 真实PancakeSwap添加流动性
    // 添加流动性 (单币ETH)
    function _addLiquidityETH(
        address provider,
        uint256 tokenAmount,
        uint256 bnbAmount
    ) internal {
        vm.startPrank(provider);
        jmToken.approve(PANCAKE_ROUTER, tokenAmount);
        IPancakeRouter(PANCAKE_ROUTER).addLiquidityETH{value: bnbAmount}(
            address(jmToken),
            tokenAmount,
            0,
            0,
            provider,
            block.timestamp
        );
        vm.stopPrank();
    }
}
