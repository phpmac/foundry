// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Withdraw} from "../../src/mc/Withdraw.sol";

/**
 * @title WithdrawScript
 * @dev Withdraw 代理合约: 读取状态 + 初始化配置
 *
 * 读取状态:
 * forge script script/mc/Withdraw.s.sol
 *
 * 执行初始化配置 (需要 broadcast):
 * forge script script/mc/Withdraw.s.sol --sig "setUp()" --broadcast
 */
contract WithdrawScript is Script {
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;

    function run() external view {
        address proxyAddress = vm.envAddress("WITHDRAW_PROXY_ADDRESS");
        require(
            proxyAddress != address(0),
            unicode"WITHDRAW_PROXY_ADDRESS 未设置"
        );

        Withdraw w = Withdraw(proxyAddress);

        console.log(unicode"=== Withdraw 合约状态 ===");
        console.log(unicode"代理地址:", proxyAddress);
        console.log(unicode"是否暂停:", w.isPause());
        console.log(unicode"签名地址:", w.withdrawalSignAddress());
        console.log(unicode"手续费接收:", w.feeReceiver());
        console.log(unicode"PancakeRouter:", w.pancakeRouter());

        // 读取 swap 路径
        console.log(unicode"\n=== Swap 路径 ===");
        for (uint256 i = 0; i < 10; i++) {
            try w.swapPath(i) returns (address token) {
                console.log(unicode"  路径[%d]:", i, token);
            } catch {
                if (i == 0) {
                    console.log(unicode"  (未设置)");
                }
                break;
            }
        }

        // 合约余额
        console.log(unicode"\n=== 合约余额 ===");
        uint256 usdtBal = IERC20(USDT).balanceOf(proxyAddress);
        console.log(unicode"USDT 余额:", usdtBal);

        console.log(unicode"========================");
    }

    /**
     * 初始化配置: 设置手续费接收地址 + swap路径
     * forge script script/mc/Withdraw.s.sol --sig "setUp()" --broadcast
     */
    function setUp() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("WITHDRAW_PROXY_ADDRESS");
        require(
            proxyAddress != address(0),
            unicode"WITHDRAW_PROXY_ADDRESS 未设置"
        );

        Withdraw w = Withdraw(proxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 设置手续费接收地址
        if (w.feeReceiver() == address(0)) {
            w.setFeeReceiver(0x4f8Db8C9aaDd66E8C107168617346ED86Af4E494);
        }

        // 设置 swap 路径: USDT -> 目标代币
        if (w.pancakeRouter() == address(0)) {
            address[] memory path = new address[](2);
            path[0] = USDT;
            path[1] = 0xb531613381ccE69DACdfe3693570f8cbf8BDA81f;

            w.setSwapConfig(PANCAKE_ROUTER, path);
            console.log(unicode"已设置 SwapConfig");
            console.log(unicode"  Router:", PANCAKE_ROUTER);
            console.log(unicode"  路径: USDT -> 0x0c7d...fb62");
        }

        vm.stopBroadcast();
    }
}
