// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MC} from "../../src/mc/MC.sol";

/**
 * @title RegisterPairScript
 * @dev Register pair to MC contract to enable sell tax
 */
contract RegisterPairScript is Script {
    // MC 合约地址
    address public constant MC_ADDRESS =
        0xE22Ef50d4FD328296E2D366b523C2348b6B319d0;

    // PancakeSwap Router 地址
    address public constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    // PancakeSwap Factory 地址
    address public constant FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;

    // USDT 地址
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    function run() external {
        // Fork BSC mainnet
        uint256 forkId = vm.createFork("bsc_mainnet");
        vm.selectFork(forkId);

        // 获取部署者私钥
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        console.log(unicode"执行账户: ", deployer);
        console.log(unicode"MC 地址: ", MC_ADDRESS);

        vm.startBroadcast(privateKey);

        MC mc = MC(MC_ADDRESS);

        // 1. 设置 Router (如果未设置)
        if (mc.pancakeRouter() == address(0)) {
            console.log(unicode"设置 PancakeRouter...");
            mc.setPancakeRouter(ROUTER);
            console.log(unicode"✓ PancakeRouter 已设置");
        } else {
            console.log(unicode"PancakeRouter 已设置: ", mc.pancakeRouter());
        }

        // 2. 获取交易对地址
        address pair = IPancakeFactory(FACTORY).getPair(MC_ADDRESS, USDT);
        console.log(unicode"交易对地址: ", pair);

        require(pair != address(0), unicode"交易对不存在, 请先创建");

        // 3. 检查当前注册状态
        bool isRegistered = mc.isPair(pair);
        console.log(unicode"当前注册状态: ", isRegistered);

        if (isRegistered) {
            console.log(unicode"⚠ 交易对已注册, 无需重复操作");
        } else {
            // 4. 注册交易对
            console.log(unicode"注册交易对...");
            mc.setPair(pair, true);
            console.log(unicode"✓ 交易对已注册");

            // 5. 验证
            require(mc.isPair(pair), unicode"注册失败");
            console.log(unicode"✓ 验证通过");
        }

        vm.stopBroadcast();

        console.log(unicode"\n=== 完成 ===");
        console.log(unicode"交易对: ", pair);
        console.log(unicode"isPair: ", mc.isPair(pair));
    }
}

interface IPancakeFactory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
}
