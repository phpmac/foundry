// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/mc/MC.sol";
import "../../src/mc/interfaces/IPancakeFactory.sol";

/**
 * @title SetupScript
 * @dev Deploy setup script: create pair, enable trading, set whitelist
 */
contract SetupScript is Script {
    MC public mc;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Already deployed MC contract address
        mc = MC(0xb531613381ccE69DACdfe3693570f8cbf8BDA81f);

        console.log(unicode"=== MC Token 部署后设置 ===");
        console.log("MC Address:", address(mc));
        console.log("Owner:", deployer);

        // 1. Create trading pair if not exists
        console.log(unicode"\n1. 检查/创建 MC/USDT 交易对...");
        address pancakeRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
        address usdt = 0x55d398326f99059fF775485246999027B3197955;

        // Check if pair exists via Factory
        address factory = IPancakeRouter(pancakeRouter).factory();
        address pair = IPancakeFactory(factory).getPair(address(mc), usdt);

        if (pair == address(0)) {
            console.log(unicode"交易对不存在, 正在创建...");
            revert("createPair is internal, deploy via MC constructor");
            console.log(unicode"交易对已创建:", pair);
        } else {
            console.log(unicode"交易对已存在:", pair);
        }

        console.log("Router:", pancakeRouter);

        // 2. Set whitelist
        console.log(unicode"\n2. 设置白名单...");
        mc.setWhitelist(pair, true);
        console.log(unicode"交易对已添加到白名单");

        mc.setWhitelist(deployer, true);
        console.log(unicode"Owner 已添加到白名单");

        // 3. Enable trading
        console.log(unicode"\n3. 开启交易...");
        mc.setTradingEnabled(true);
        console.log(unicode"交易已开启! Trading enabled!");

        vm.stopBroadcast();

        console.log(unicode"\n=== 设置完成 ====");
        console.log("Pair Address:", pair);
        console.log("Trading Enabled:", mc.tradingEnabled());
    }
}
