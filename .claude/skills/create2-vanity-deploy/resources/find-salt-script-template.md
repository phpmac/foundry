# FindVanitySalt 脚本模板

用于搜索 CREATE2 靓号地址的 salt.

## 核心逻辑

```solidity
// initCode = creationCode + encoded constructor args
bytes memory initCode = abi.encodePacked(
    type(YourContract).creationCode,
    abi.encode(constructorArgs...)
);
bytes32 initCodeHash = keccak256(initCode);

// 暴力搜索 salt
for (uint256 i = 0; i < maxIter; i++) {
    address predicted = _computeCreate2Address(deployer, bytes32(i), initCodeHash);

    bool isMatch;
    if (isSuffix) {
        // 后缀匹配: 取最后 16 bit
        isMatch = (uint160(predicted) & 0xFFFF) == target;
    } else {
        // 前缀匹配: 取最高 16 bit
        isMatch = (uint160(predicted) >> 144) == target;
    }

    if (isMatch) {
        salt = bytes32(i);
        break;
    }
}
```

## CREATE2 地址计算

```solidity
function _computeCreate2Address(
    address deployer,
    bytes32 salt,
    bytes32 initCodeHash
) internal pure returns (address) {
    return address(
        uint160(uint256(keccak256(
            abi.encodePacked(hex"ff", deployer, salt, initCodeHash)
        )))
    );
}
```

## 环境变量

```bash
VANITY_TARGET=0x1111          # 目标 (默认 0x1111)
VANITY_MAX_ITER=500000        # 最大迭代 (默认 500000)
VANITY_MODE=suffix            # suffix 或 prefix
```

## 执行

```bash
forge script script/<path>/FindVanitySalt.s.sol --offline
```
