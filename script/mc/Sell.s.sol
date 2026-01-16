// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MC} from "../../src/mc/MC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPancakeRouter} from "../../src/mc/interfaces/IPancakeRouter.sol";

/**
 * 主网模拟卖出测试
 * @title SellScript
 * @dev 卖出 MC 脚本
 */
contract SellScript is Script {
    address constant MC_ADDRESS = 0xcD0c229a02a9fBCbb6a19347a48d004c46d7e4d1;
    address constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address constant FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    function run() external {
        // Fork BSC mainnet
        uint256 forkId = vm.createFork("bsc_mainnet");
        vm.selectFork(forkId);

        // 指定卖家地址
        address seller = 0x1C3314831ff9a25178a4F179237a8cfA56A2cb6A;

        MC mc = MC(MC_ADDRESS);
        IERC20 usdt = IERC20(USDT);

        // 卖出数量
        uint256 sellAmount = 0.00001 ether;

        console.log(unicode"=== MC 卖出测试 ===");
        console.log(unicode"卖家地址: ", seller);
        console.log(unicode"MC 余额: ", mc.balanceOf(seller));
        console.log(unicode"卖出数量: ", sellAmount);

        // 记录初始状态
        uint256 mcBefore = mc.balanceOf(seller);
        require(mcBefore >= sellAmount, "MC balance is not enough");
        uint256 deadBalance = mc.balanceOf(DEAD);
        uint256 usdtBefore = usdt.balanceOf(seller);

        // 使用 getAmountsOut 计算预期输出
        address[] memory path = new address[](2);
        path[0] = MC_ADDRESS;
        path[1] = USDT;

        uint256[] memory amounts = IPancakeRouter(ROUTER).getAmountsOut(
            sellAmount,
            path
        );
        uint256 expectedOutput = amounts[1];

        // 12% 滑点: 最少输出 = 预期输出 * 88%
        uint256 amountOutMin = (expectedOutput * 88) / 100;

        console.log(unicode"预期输出 USDT: ", expectedOutput);
        console.log(unicode"最小输出 (12%滑点): ", amountOutMin);

        // 执行卖出
        vm.startPrank(seller);
        mc.approve(ROUTER, type(uint256).max);
        {
            (bool success, ) = ROUTER.call(
                abi.encodeWithSignature(
                    "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                    sellAmount,
                    amountOutMin,
                    path,
                    seller,
                    block.timestamp + 3600
                )
            );
            require(success, unicode"交易失败");
        }
        vm.stopPrank();

        // 计算结果 - 使用独立作用域减少堆栈深度
        console.log(unicode"\n=== 卖出结果 ===");
        {
            uint256 mcAfter = mc.balanceOf(seller);
            console.log(unicode"实际花费 MC: ", mcBefore - mcAfter);
        }
        {
            console.log(
                unicode"黑洞销毁 (3%): ",
                mc.balanceOf(DEAD) - deadBalance
            );
        }
        {
            uint256 usdtAfter = usdt.balanceOf(seller);
            console.log(unicode"USDT 变化: ", usdtAfter - usdtBefore);
        }
        console.log(unicode"✓ 卖出完成");
    }
}

interface IPancakeFactory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address);
}
