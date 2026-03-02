// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/jm/JMToken.sol";
import "../../src/jm/LPDistributor.sol";

/**
 * @title DeployJM
 * @dev JM Token 部署脚本
 *
 * 部署流程:
 * 1. 部署 JMToken
 * 2. 部署 LPDistributor (内置JMB凭证)
 * 3. 配置合约关联
 */
contract DeployJM is Script {
    // BSC主网 PancakeSwap Router
    address constant PANCAKE_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log(unicode"开始部署 JM Token...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 JMToken
        JMToken jmToken = new JMToken(PANCAKE_ROUTER);
        console.log("JMToken deployed at:", address(jmToken));
        console.log("LP Pair:", jmToken.lpPair());

        // 2. 部署 LPDistributor
        LPDistributor lpDistributor = new LPDistributor(
            address(jmToken),
            jmToken.lpPair()
        );
        console.log("LPDistributor deployed at:", address(lpDistributor));

        // 3. 配置合约关联
        jmToken.setLPDistributor(address(lpDistributor));

        console.log(unicode"部署完成!");
        console.log("JMToken:", address(jmToken));
        console.log("JMB Voucher is built in LPDistributor");
        console.log("LPDistributor:", address(lpDistributor));
        console.log("LP Pair:", jmToken.lpPair());

        vm.stopBroadcast();
    }
}
