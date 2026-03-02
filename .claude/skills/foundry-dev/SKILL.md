---
name: foundry-dev
description: Use when 用户提到 forge/foundry/编译/测试/部署智能合约
---

# Foundry开发指南

## 核心命令

| 命令 | 说明 |
|------|------|
| `forge build` | 编译合约 |
| `forge test` | 运行测试 |
| `forge test -vvv` | 详细输出 |
| `forge fmt` | 格式化代码 |
| `forge coverage` | 测试覆盖率 |
| `forge snapshot` | Gas快照 |

## 代码规范

- SPDX: `// SPDX-License-Identifier: UNLICENSED`
- 版本: `pragma solidity ^0.8.13;`
- 合约: 帕斯卡命名 (MyContract)
- 函数/变量: 驼峰命名 (myFunction)
- 测试函数: `test_` 或 `testFuzz_` 前缀
- 测试合约: `<ContractName>Test`

## 项目结构

```
src/     - 合约源代码
test/    - 测试文件
script/  - 部署脚本
lib/     - 依赖库
```

## 调试

- `console.log()` - 需导入 `forge-std/console.sol`
- 中文日志: `console.log(unicode"中文")`
- `forge test -vvvv` - 查看调用栈

## 安全检查

- 不要硬编码私钥
- 部署前运行完整测试
- 注意重入攻击和整数溢出

## 提交规范

- 提交前: `forge test` + `forge fmt`
- 合约修改必须更新测试
