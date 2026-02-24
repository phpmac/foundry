// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SimpleToken} from "../../src/simple/SimpleToken.sol";

/**
 * @title ReadUSDTScript
 * @dev SimpleToken (USDT) 状态读取脚本
 *
 * 读取状态:
 * forge script script/bird-points/ReadUSDT.s.sol --rpc-url eni
 *
 * 环境变量:
 * USDT_PROXY_ADDRESS - USDT 代理合约地址
 */
contract ReadUSDTScript is Script {
    function run() external view {
        address proxyAddress = vm.envAddress("USDT_PROXY_ADDRESS");
        require(proxyAddress != address(0), unicode"USDT_PROXY_ADDRESS 未设置");

        SimpleToken token = SimpleToken(proxyAddress);

        console.log(unicode"=== SimpleToken (USDT) 合约状态 ===");
        console.log(unicode"代理地址:", proxyAddress);
        console.log(unicode"代币名称:", token.name());
        console.log(unicode"代币符号:", token.symbol());
        console.log(unicode"代币精度:", token.decimals());
        console.log(unicode"代币总量:", token.totalSupply() / 1e18);

        console.log(unicode"\n========================");
    }
}
