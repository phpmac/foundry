// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

/**
 * @title FindVanityAddress
 * @dev 寻找能部署出靓号代币合约地址的部署者私钥
 *
 * 使用方法:
 * 1. 运行此脚本寻找私钥: forge script script/jm/FindVanityAddress.s.sol --sig "findVanity(uint256,uint256)" 1111 <随机种子>
 *    例如: forge script script/jm/FindVanityAddress.s.sol --sig "findVanity(uint256,uint256)" 1111 12345
 *    每次使用不同的种子会得到不同的私钥
 * 2. 使用找到的私钥部署: PRIVATE_KEY=找到的私钥 forge script script/jm/DeployJM.s.sol --broadcast
 */
contract FindVanityAddress is Script {
    /**
     * @dev 寻找能产生特定尾号的部署者私钥
     * @param targetSuffix 目标尾号 (如 1111, 2222, 3333 等)
     *        输入的十进制数字会被解析为十六进制后缀
     *        例如: 1111 -> 寻找 0x1111 (十进制 4369)
     */
    function findVanity(uint256 targetSuffix, uint256 seed) external {
        require(
            targetSuffix >= 1000 && targetSuffix <= 9999,
            "Target must be 4 digits"
        );

        // 将十进制输入解析为十六进制数值
        // 例如: 1111 -> 0x1111 = 4369
        uint256 hexTarget = _decimalToHex(targetSuffix);

        console.log(unicode"开始寻找靓号代币合约地址...");
        console.log(unicode"目标后缀(十进制输入):", targetSuffix);
        console.log(unicode"目标后缀(十六进制值):", hexTarget);
        console.log(unicode"随机种子:", seed);
        console.log(
            unicode"目标后缀(十六进制格式):",
            vm.toString(bytes32(hexTarget))
        );

        uint256 found = 0;
        uint256 attempts = 0;

        while (found < 1) {
            attempts++;

            // 生成随机私钥 - 使用种子+尝试次数+时间戳确保每次不同
            uint256 privateKey = uint256(
                keccak256(
                    abi.encodePacked(seed, attempts, block.timestamp, gasleft())
                )
            );

            // 确保私钥在有效范围内 (1 到 secp256k1 曲线阶数-1)
            privateKey =
                (privateKey %
                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140) +
                1;

            address deployer = vm.addr(privateKey);

            // 计算部署后的合约地址 (nonce = 0, 第一个部署的合约)
            address tokenAddr = _computeContractAddress(deployer, 0);

            // 检查尾号 (十六进制后4位)
            uint256 suffix = uint256(uint160(tokenAddr)) % 0x10000;

            if (suffix == hexTarget) {
                found++;
                console.log("=================================");
                console.log(unicode"找到候选 #", found);
                console.log(
                    unicode"私钥(HEX):",
                    vm.toString(bytes32(privateKey))
                );
                console.log(unicode"部署者地址:", deployer);
                console.log(unicode"代币地址:", tokenAddr);
                console.log(unicode"后缀(十进制):", suffix);
                console.log(
                    unicode"后缀(十六进制):",
                    vm.toString(bytes32(suffix))
                );
                console.log("=================================");

                if (found >= 1) {
                    break;
                }
            }

            if (attempts % 100000 == 0) {
                console.log(unicode"已尝试次数:", attempts);
            }
        }

        console.log(unicode"总共尝试次数:", attempts);
        console.log(unicode"\n使用说明:");
        console.log(unicode"1. 复制上面任一 Private Key");
        console.log(unicode"2. 在 .env 文件中设置: PRIVATE_KEY=你的私钥");
        console.log(
            unicode"3. 运行: forge script script/jm/DeployJM.s.sol --broadcast"
        );
    }

    /**
     * @dev 计算合约地址 (基于部署者地址和nonce)
     * CREATE地址公式: address = keccak256(RLP(deployer, nonce))[12:32]
     */
    function _computeContractAddress(
        address deployer,
        uint256 nonce
    ) internal pure returns (address) {
        bytes memory rlpEncoded;

        if (nonce == 0x00) {
            // RLP([deployer, 0]) = 0xd6 0x94 deployer 0x80
            rlpEncoded = abi.encodePacked(
                bytes1(0xd6),
                bytes1(0x94),
                bytes20(deployer),
                bytes1(0x80)
            );
        } else if (nonce <= 0x7f) {
            // RLP([deployer, nonce]) = 0xd7 0x94 deployer nonce
            rlpEncoded = abi.encodePacked(
                bytes1(0xd7),
                bytes1(0x94),
                bytes20(deployer),
                bytes1(uint8(nonce))
            );
        } else if (nonce <= 0xff) {
            // RLP([deployer, nonce]) = 0xd8 0x94 deployer 0x81 nonce
            rlpEncoded = abi.encodePacked(
                bytes1(0xd8),
                bytes1(0x94),
                bytes20(deployer),
                bytes1(0x81),
                bytes1(uint8(nonce))
            );
        } else if (nonce <= 0xffff) {
            // RLP([deployer, nonce]) = 0xd9 0x94 deployer 0x82 nonce (2 bytes)
            rlpEncoded = abi.encodePacked(
                bytes1(0xd9),
                bytes1(0x94),
                bytes20(deployer),
                bytes1(0x82),
                uint16(nonce)
            );
        } else {
            // nonce > 0xffff, use 4 bytes
            rlpEncoded = abi.encodePacked(
                bytes1(0xda),
                bytes1(0x94),
                bytes20(deployer),
                bytes1(0x84),
                uint32(nonce)
            );
        }

        return address(uint160(uint256(keccak256(rlpEncoded))));
    }

    /**
     * @dev 将十进制数字解析为十六进制数值
     * 例如: 1111 (十进制) -> 0x1111 = 4369 (十进制)
     * 即将每一位十进制数字当作十六进制的一位
     */
    function _decimalToHex(uint256 decimal) internal pure returns (uint256) {
        uint256 result = 0;
        uint256 multiplier = 1;
        uint256 temp = decimal;

        while (temp > 0) {
            uint256 digit = temp % 10;
            require(digit <= 15, "Invalid hex digit");
            result += digit * multiplier;
            multiplier *= 16;
            temp /= 10;
        }

        return result;
    }

    /**
     * @dev 验证一个私钥对应的代币合约地址
     * @param privateKey 部署者私钥
     */
    function verifyPrivateKey(uint256 privateKey) external pure {
        address deployer = vm.addr(privateKey);
        address tokenAddr = _computeContractAddress(deployer, 0);
        uint256 suffix = uint256(uint160(tokenAddr)) % 0x10000;

        console.log("=================================");
        console.log(unicode"私钥(HEX):", vm.toString(bytes32(privateKey)));
        console.log(unicode"部署者地址:", deployer);
        console.log(unicode"代币地址:", tokenAddr);
        console.log(unicode"后缀(十进制):", suffix);
        console.log(unicode"后缀(十六进制):", vm.toString(bytes32(suffix)));
        console.log("=================================");
    }
}
