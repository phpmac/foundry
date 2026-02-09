// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/**
 * @title FindVanityAddress
 * @dev 寻找能部署出靓号代币合约地址的部署者私钥
 *
 * 使用方法:
 * 1. 运行此脚本寻找私钥: forge script script/jm/FindVanityAddress.s.sol --sig "findVanity(uint256)" 1111
 * 2. 使用找到的私钥部署: PRIVATE_KEY=找到的私钥 forge script script/jm/DeployJM.s.sol --broadcast
 */
contract FindVanityAddress is Script {

    /**
     * @dev 寻找能产生特定尾号的部署者私钥
     * @param targetSuffix 目标尾号 (如 1111, 2222, 3333 等)
     */
    function findVanity(uint256 targetSuffix) external {
        require(targetSuffix >= 1000 && targetSuffix <= 9999, "Target must be 4 digits");

        console.log(unicode"开始寻找靓号代币合约地址...");
        console.log("Target suffix:", targetSuffix);

        uint256 found = 0;
        uint256 attempts = 0;

        while (found < 5) {
            attempts++;

            // 生成随机私钥
            uint256 privateKey = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                msg.sender,
                attempts,
                block.prevrandao
            )));

            address deployer = vm.addr(privateKey);

            // 计算部署后的合约地址 (nonce = 0, 第一个部署的合约)
            address tokenAddr = _computeContractAddress(deployer, 0);

            // 检查尾号
            uint256 suffix = uint256(uint160(tokenAddr)) % 10000;

            if (suffix == targetSuffix) {
                found++;
                console.log("=================================");
                console.log(unicode"找到候选 #", found);
                console.log("Private Key (HEX):", vm.toString(bytes32(privateKey)));
                console.log("Deployer Address:", deployer);
                console.log("Token Address:", tokenAddr);
                console.log("Suffix:", suffix);
                console.log("=================================");
            }

            if (attempts % 100000 == 0) {
                console.log(unicode"已尝试次数:", attempts);
            }
        }

        console.log(unicode"总共尝试次数:", attempts);
        console.log(unicode"\n使用说明:");
        console.log(unicode"1. 复制上面任一 Private Key");
        console.log(unicode"2. 在 .env 文件中设置: PRIVATE_KEY=你的私钥");
        console.log(unicode"3. 运行: forge script script/jm/DeployJM.s.sol --broadcast");
    }

    /**
     * @dev 计算合约地址 (基于部署者地址和nonce)
     */
    function _computeContractAddress(address deployer, uint256 nonce) internal pure returns (address) {
        bytes memory rlpEncoded;

        if (nonce == 0x00) {
            rlpEncoded = abi.encodePacked(
                bytes1(0xd6),
                bytes1(0x94),
                deployer,
                bytes1(0x80)
            );
        } else if (nonce <= 0x7f) {
            rlpEncoded = abi.encodePacked(
                bytes1(0xd6),
                bytes1(0x94),
                deployer,
                bytes1(uint8(nonce))
            );
        } else if (nonce <= 0xff) {
            rlpEncoded = abi.encodePacked(
                bytes1(0xd7),
                bytes1(0x94),
                deployer,
                bytes1(0x81),
                bytes1(uint8(nonce))
            );
        } else {
            rlpEncoded = abi.encodePacked(
                bytes1(0xd8),
                bytes1(0x94),
                deployer,
                bytes1(0x82),
                uint16(nonce)
            );
        }

        bytes32 hash = keccak256(rlpEncoded);
        return address(uint160(uint256(hash)));
    }

    /**
     * @dev 验证一个私钥对应的代币合约地址
     * @param privateKey 部署者私钥
     */
    function verifyPrivateKey(uint256 privateKey) external view {
        address deployer = vm.addr(privateKey);
        address tokenAddr = _computeContractAddress(deployer, 0);
        uint256 suffix = uint256(uint160(tokenAddr)) % 10000;

        console.log("=================================");
        console.log("Private Key (HEX):", vm.toString(bytes32(privateKey)));
        console.log("Deployer Address:", deployer);
        console.log("Token Address:", tokenAddr);
        console.log("Suffix:", suffix);
        console.log("=================================");
    }
}
