# Deploy 脚本模板

用于使用已找到的 salt 部署合约.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

contract DeployVanity is Script {
    function run() external {
        bytes32 salt = vm.envBytes32("VANITY_SALT");
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        YourContract c = new YourContract{salt: salt}(constructorArgs...);
        console.log(unicode"部署地址:", address(c));

        vm.stopBroadcast();
    }
}
```

## 执行

```bash
forge script script/<path>/DeployVanity.s.sol --broadcast
```
