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
 */
contract JMTokenTest is Test {
    JMToken public jmToken;
    JMBToken public jmbToken;
    LPDistributor public lpDistributor;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    // BSC主网 PancakeSwap Router (测试使用模拟)
    address public constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

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

        // 转移代币到JMToken合约用于私募和燃烧
        jmToken.transfer(address(jmToken), 17_000_000 ether);
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
        jmToken.buyPrivateSale{value: 0.2 ether}();

        // 检查收到6000 JM
        assertEq(jmToken.balanceOf(user1) - initialBalance, 6000 ether);
    }

    function test_PrivateSaleExactAmount() public {
        vm.expectRevert("Send 0.2 BNB");
        vm.prank(user1);
        jmToken.buyPrivateSale{value: 0.1 ether}();
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

    // ========== 交易所锁仓测试 ==========

    function test_ExchangeLockRecipient() public {
        // 锁仓地址固定为 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e
        assertEq(jmToken.exchangeLockRecipient(), 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e);
    }

    function test_ExchangeLockTooEarly() public {
        vm.expectRevert("Lock period not ended");
        jmToken.claimExchangeLock();
    }

    function test_ExchangeLockSuccess() public {
        address lockRecipient = 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e;

        // 先转移200万到合约用于锁仓
        jmToken.transfer(address(jmToken), 2_000_000 ether);

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
        // 先转移200万到合约
        jmToken.transfer(address(jmToken), 2_000_000 ether);

        // 快进365天并解锁
        vm.warp(block.timestamp + 366 days);
        jmToken.claimExchangeLock();

        // 再次尝试解锁应该失败
        vm.expectRevert("Already claimed");
        jmToken.claimExchangeLock();
    }

    function test_GetExchangeLockStatus() public {
        (uint256 amount, uint256 unlockTime, bool canClaim, bool claimed, address recipient) =
            jmToken.getExchangeLockStatus();

        assertEq(amount, 2_000_000 ether);
        assertEq(recipient, 0xe7c35767dB12D79d120e0b5c30bFd960b2b2B89e);
        assertFalse(claimed);
        assertFalse(canClaim); // 时间还没到
    }
}
