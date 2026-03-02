# CREATE2 单元测试模板

用于验证: 搜索 salt -> 部署 -> 校验后缀.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/Counter.sol";

contract Create2VanityTest is Test {
    function testVanityDeploy() public {
        bytes32 initCodeHash = keccak256(type(Counter).creationCode);
        address deployer = address(this);
        uint256 target = 0x1111; // 目标后缀

        bytes32 salt;
        address predicted;
        for (uint256 i = 0; i < 500000; i++) {
            predicted = _computeAddr(deployer, bytes32(i), initCodeHash);
            bool isMatch = (uint160(predicted) & 0xFFFF) == target; // 后缀匹配
            if (isMatch) {
                salt = bytes32(i);
                break;
            }
        }

        require(predicted != address(0), unicode"未找到 salt");
        Counter c = new Counter{salt: salt}();

        assertEq(address(c), predicted);
        assertEq(uint160(address(c)) & 0xFFFF, target);
    }

    function _computeAddr(address d, bytes32 s, bytes32 h) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", d, s, h)))));
    }
}
```

执行:

```bash
forge test --match-path test/jm/Create2Vanity.t.sol -vvv --offline
```

前缀或任意匹配建议用命令:

```bash
cast create2 --starts-with 1111 --init-code $(forge inspect Counter bytecode)
cast create2 --matching 8888 --init-code $(forge inspect Counter bytecode)
```
