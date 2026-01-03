// SPDX-License-Identifier: UNLICENSED
// 运行测试命令: forge test --match-contract D3xaiRecycleTest -vvv
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {D3xai} from "../src/D3xai.sol";
import {IPancakePair} from "../src/interface/IPancakePair.sol";

// BSC主网D3xai合约地址
address constant D3XAI_ADDRESS = 0x655d54f845cE60a07869d409109A6823367465B2;

contract D3xaiRecycleTest is Test {
    D3xai public d3xai;
    IPancakePair public pair;

    function setUp() public {
        // fork BSC主网
        vm.createSelectFork("https://bsc-dataseed.binance.org");

        d3xai = D3xai(D3XAI_ADDRESS);
        pair = d3xai.pair();

        // 如果pair未设置则跳过测试
        if (address(pair) == address(0)) {
            vm.skip(true);
        }
    }

    /**
     * 测试销毁底池3%后价格变化
     * 理论上: 销毁D3xai后,底池中D3xai减少,价格上涨
     * AMM公式: price = reserveUSDT / reserveD3xai
     * 销毁3%后: newPrice = reserveUSDT / (reserveD3xai * 0.97) = price / 0.97 ≈ price * 1.0309
     */
    function test_RecycleBurnsPairTokensAndIncreasesPrice() public {
        // 获取销毁前的价格和底池余额
        uint256 priceBefore = d3xai.price();
        uint256 pairBalanceBefore = d3xai.balanceOf(address(pair));

        console.log("=== Before Recycle ===");
        console.log("Price:", priceBefore);
        console.log("Pair Balance:", pairBalanceBefore);

        // 计算要销毁的数量 (底池的3%)
        uint256 burnAmount = (pairBalanceBefore * 3) / 100;
        console.log("burnAmount:", burnAmount);

        // 模拟拥有SELL_ROLE的地址执行销毁
        // tokenSellContract 已经有SELL_ROLE权限
        address tokenSellContract = d3xai.tokenSellContract();
        console.log("tokenSellContract:", tokenSellContract);

        // 执行销毁
        vm.prank(tokenSellContract);
        d3xai.recycle(burnAmount);

        // 获取销毁后的价格和底池余额
        uint256 priceAfter = d3xai.price();
        uint256 pairBalanceAfter = d3xai.balanceOf(address(pair));

        console.log("=== After Recycle ===");
        console.log("Price:", priceAfter);
        console.log("Pair Balance:", pairBalanceAfter);
        console.log("Burned Amount:", pairBalanceBefore - pairBalanceAfter);

        // 验证: 底池余额减少
        assertLt(
            pairBalanceAfter,
            pairBalanceBefore,
            "Pair balance should decrease"
        );

        // 验证: 价格上涨
        assertGt(priceAfter, priceBefore, "Price should increase after burn");

        // 计算价格涨幅 (乘以10000避免精度丢失)
        uint256 priceIncreaseBps = ((priceAfter - priceBefore) * 10000) /
            priceBefore;
        console.log("Price increase (bps):", priceIncreaseBps);

        // 销毁3%理论上价格涨幅约为3.09% (309bps)
        // 允许一定误差范围 (250-400 bps)
        assertGt(priceIncreaseBps, 250, "Price increase should be > 2.5%");
        assertLt(priceIncreaseBps, 400, "Price increase should be < 4%");
    }
}
