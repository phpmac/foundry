// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BuyHashNft} from "../../src/bird-points/BuyHashNft.sol";
import {HashNft} from "../../src/bird-points/HashNft.sol";

/**
 * @title DeployBuyHashNftScript
 * @dev BuyHashNft 合约部署脚本: 部署可升级的 BuyHashNft 和 HashNft 合约
 *
 * 运行命令:
 * forge script script/bird-points/DeployBuyHashNft.s.sol --rpc-url eni --broadcast
 *
 * 环境变量:
 * - PRIVATE_KEY: 部署者私钥
 * - USDT_PROXY_ADDRESS: USDT 合约地址
 * - INVITE_PROXY_ADDRESS: 邀请合约地址
 * - TREASURY_WALLET: 收款钱包地址
 */
contract DeployBuyHashNftScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // 读取环境变量
        address usdtAddress = vm.envAddress("USDT_PROXY_ADDRESS");
        address inviteAddress = vm.envAddress("INVITE_PROXY_ADDRESS");
        address treasuryWallet = vm.envAddress("TREASURY_WALLET");

        console.log(unicode"=== 配置检查 ===");
        console.log(unicode"部署者地址:", deployer);
        console.log(unicode"部署者 ETH 余额:", deployer.balance / 1e18);
        console.log(unicode"USDT 地址:", usdtAddress);
        console.log(unicode"Invite 地址:", inviteAddress);
        console.log(unicode"Treasury 钱包:", treasuryWallet);
        console.log(unicode"================\n");

        require(usdtAddress != address(0), unicode"USDT_PROXY_ADDRESS 未设置");
        require(inviteAddress != address(0), unicode"INVITE_PROXY_ADDRESS 未设置");
        require(treasuryWallet != address(0), unicode"TREASURY_WALLET 未设置");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 HashNft 实现合约
        console.log(unicode"部署 HashNft 实现合约...");
        HashNft nftImpl = new HashNft();
        console.log(unicode"实现合约地址:", address(nftImpl));

        // 初始化数据
        bytes memory nftInitData = abi.encodeWithSelector(
            HashNft.initialize.selector,
            "HashNft",
            "HNFT"
        );

        // 部署 HashNft 代理合约
        console.log(unicode"部署 HashNft 代理合约...");
        ERC1967Proxy nftProxy = new ERC1967Proxy(address(nftImpl), nftInitData);
        console.log(unicode"代理合约地址:", address(nftProxy));

        HashNft nft = HashNft(address(nftProxy));

        // 部署 BuyHashNft 实现合约
        console.log(unicode"部署 BuyHashNft 实现合约...");
        BuyHashNft buyHashNftImpl = new BuyHashNft();
        console.log(unicode"实现合约地址:", address(buyHashNftImpl));

        // 初始化数据
        bytes memory buyHashNftInitData = abi.encodeWithSelector(
            BuyHashNft.initialize.selector,
            usdtAddress,
            address(nftProxy),
            inviteAddress,
            treasuryWallet
        );

        // 部署 BuyHashNft 代理合约
        console.log(unicode"部署 BuyHashNft 代理合约...");
        ERC1967Proxy buyHashNftProxy = new ERC1967Proxy(address(buyHashNftImpl), buyHashNftInitData);
        console.log(unicode"代理合约地址:", address(buyHashNftProxy));

        BuyHashNft buyHashNft = BuyHashNft(address(buyHashNftProxy));

        // 给 BuyHashNft 授予 MINTER_ROLE
        console.log(unicode"授予 BuyHashNft MINTER_ROLE...");
        nft.grantRole(nft.MINTER_ROLE(), address(buyHashNftProxy));

        // 执行健康检查
        console.log(unicode"执行健康检查...");
        buyHashNft.healthcheck();
        console.log(unicode"健康检查通过");

        vm.stopBroadcast();

        console.log(unicode"\n=== 部署摘要 ===");
        console.log(unicode"HashNft 实现:", address(nftImpl));
        console.log(unicode"HashNft 代理:", address(nftProxy));
        console.log(unicode"BuyHashNft 实现:", address(buyHashNftImpl));
        console.log(unicode"BuyHashNft 代理 (使用此地址):", address(buyHashNftProxy));
        console.log(unicode"管理员:", deployer);
        console.log(unicode"Treasury:", treasuryWallet);
        console.log(unicode"NFT 价格: 500 USDT");
    }
}