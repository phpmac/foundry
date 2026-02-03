// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SimpleToken} from "../../src/simple/SimpleToken.sol";

/**
 * @title TransferOwnershipScript
 * @dev SimpleToken 权限转移脚本
 *
 * 运行命令:
 * forge script script/simple/TransferOwnership.s.sol --rpc-url bsc_mainnet --broadcast
 */
contract TransferOwnershipScript is Script {
    address public constant TOKEN_ADDRESS = address(0);
    address public constant NEW_ADMIN = address(0);
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    function run() external {
        SimpleToken token = SimpleToken(TOKEN_ADDRESS);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        token.grantRole(DEFAULT_ADMIN_ROLE, NEW_ADMIN);
        vm.stopBroadcast();

        require(
            token.hasRole(DEFAULT_ADMIN_ROLE, NEW_ADMIN),
            "transfer failed"
        );
        console.log(unicode"权限转移成功");
    }
}
