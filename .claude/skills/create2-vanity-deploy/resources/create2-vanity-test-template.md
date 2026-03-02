# CREATE2 单元测试模板

用于验证: 从 .env 读取 salt -> 部署 -> 校验地址一致.

关键点:
- 使用 `vm.prank(deployer)` 确保与实际部署者一致
- initCode 必须包含构造函数参数

```solidity
// initCode = creationCode + encoded constructor args
bytes memory initCode = abi.encodePacked(
    type(YourContract).creationCode,
    abi.encode(constructorArg1, constructorArg2)
);
bytes32 initCodeHash = keccak256(initCode);

// 计算预期地址
address predicted = _computeAddr(deployer, salt, initCodeHash);

// 使用 vm.prank 模拟从 deployer 地址部署
vm.prank(deployer);
YourContract c = new YourContract{salt: salt}(constructorArg1, constructorArg2);

// 验证
assertEq(address(c), predicted);
```

## CREATE2 地址计算

```solidity
function _computeAddr(address d, bytes32 s, bytes32 h) internal pure returns (address) {
    return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", d, s, h)))));
}
```

## 执行

```bash
forge test --match-path test/<path>/Create2Vanity.t.sol -vvv --offline
```
