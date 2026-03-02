// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/jm/JMToken.sol";

/**
 * @title FindVanitySalt
 * @dev 搜索 CREATE2 靓号地址的 salt
 *
 * 用法:
 *   forge script script/jm/FindVanitySalt.s.sol --offline
 *
 * 配置 (.env):
 *   PANCAKE_ROUTER=0x10ED43C718714eb63d5aA57B78B54704E256024E
 *   VANITY_TARGET=0x1111          # 目标后缀 (默认 0x1111)
 *   VANITY_MAX_ITER=500000        # 最大迭代次数 (默认 500000)
 *   VANITY_MODE=suffix            # suffix(后缀) 或 prefix(前缀)
 */
contract FindVanitySalt is Script {
    function run() external {
        address pancakeRouter = vm.envAddress("PANCAKE_ROUTER");
        uint256 target = vm.envOr("VANITY_TARGET", uint256(0x1111));
        uint256 maxIter = vm.envOr("VANITY_MAX_ITER", uint256(500000));
        string memory modeStr = vm.envOr("VANITY_MODE", string("suffix"));
        bool isSuffix = keccak256(bytes(modeStr)) == keccak256(bytes("suffix"));

        // 计算 initCode: bytecode + encoded constructor args
        bytes memory creationCode = type(JMToken).creationCode;
        bytes memory initCode = abi.encodePacked(
            creationCode,
            abi.encode(pancakeRouter)
        );
        bytes32 initCodeHash = keccak256(initCode);

        // 部署者地址 (广播时的 msg.sender)
        address deployer = vm.envUint("PRIVATE_KEY") != 0
            ? vm.addr(vm.envUint("PRIVATE_KEY"))
            : address(this);

        console.log(unicode"部署者地址:", deployer);
        console.log(unicode"PancakeRouter:", pancakeRouter);
        console.log(unicode"目标:", isSuffix ? unicode"后缀" : unicode"前缀");
        console.log("Target: 0x", target);
        console.log("Max iterations:", maxIter);
        console.log(unicode"--------------------------------");

        // 搜索 salt
        bytes32 salt;
        address predicted;
        uint256 foundAt = 0;

        for (uint256 i = 0; i < maxIter; i++) {
            predicted = _computeCreate2Address(
                deployer,
                bytes32(i),
                initCodeHash
            );

            bool isMatch;
            if (isSuffix) {
                // 后缀匹配: 取最后 16 bit
                isMatch = (uint160(predicted) & 0xFFFF) == target;
            } else {
                // 前缀匹配: 取最高 16 bit (地址前4位)
                isMatch = (uint160(predicted) >> 144) == target;
            }

            if (isMatch) {
                salt = bytes32(i);
                foundAt = i;
                break;
            }

            // 进度显示
            if (i > 0 && i % 100000 == 0) {
                console.log("Searched:", i);
            }
        }

        require(foundAt > 0, unicode"未找到匹配的 salt");

        console.log(unicode"--------------------------------");
        console.log(unicode"找到靓号地址:", predicted);
        console.log("Salt (decimal):", foundAt);
        console.log(unicode"--------------------------------");
        console.log(unicode"将以下内容添加到 .env:");
        // bytes32 转 hex 字符串 (VANITY_SALT=0x...)
        bytes32 saltHex = salt;
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(78);
        result[0] = "V"; result[1] = "A"; result[2] = "N"; result[3] = "I"; result[4] = "T";
        result[5] = "Y"; result[6] = "_"; result[7] = "S"; result[8] = "A"; result[9] = "L";
        result[10] = "T"; result[11] = "="; result[12] = "0"; result[13] = "x";
        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(saltHex[i]);
            result[14 + i * 2] = hexChars[b >> 4];
            result[15 + i * 2] = hexChars[b & 0x0f];
        }
        console.log(string(result));
    }

    /**
     * @dev 计算 CREATE2 地址
     * address = keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))[12:]
     */
    function _computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                deployer,
                                salt,
                                initCodeHash
                            )
                        )
                    )
                )
            );
    }
}
