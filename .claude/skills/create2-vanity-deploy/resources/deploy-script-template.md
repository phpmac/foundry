# Deploy 脚本模板

默认示例使用 `Counter`, 可直接运行.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../../src/Counter.sol";

contract DeployVanity is Script {
    function run() external {
        bytes32 salt = vm.envBytes32("VANITY_SALT");
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        Counter c = new Counter{salt: salt}();
        console.log(unicode"部署地址:", address(c));
        vm.stopBroadcast();
    }
}
```

执行:

```bash
forge script script/jm/DeployVanity.s.sol --broadcast
```
