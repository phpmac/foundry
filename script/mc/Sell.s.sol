// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MC} from "../../src/mc/MC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
        address seller = 0x130151AFa86CD285223f95BBc1e5Aa99eef8B7F2;

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
        uint256 deadBefore = mc.balanceOf(DEAD);

        // 模拟卖出 (使用 prank)
        vm.startPrank(seller);
        mc.approve(ROUTER, type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = MC_ADDRESS;
        path[1] = USDT;

        ROUTER.call(
            abi.encodeWithSignature(
                "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)",
                sellAmount,
                0,
                path,
                seller,
                block.timestamp + 3600
            )
        );
        vm.stopPrank();

        // 结果
        uint256 mcSpent = mcBefore - mc.balanceOf(seller);
        uint256 burned = mc.balanceOf(DEAD) - deadBefore;

        console.log(unicode"\n=== 卖出结果 ===");
        console.log(unicode"实际花费 MC: ", mcSpent);
        console.log(unicode"黑洞销毁 (3%): ", burned);
        console.log(unicode"收到 USDT: ", usdt.balanceOf(seller));
        console.log(unicode"✓ 卖出完成");
    }
}
