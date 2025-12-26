# AGENTS.md

## 项目概述

这是一个基于Foundry的Solidity智能合约开发项目,包含一个简单的Counter合约示例。项目使用Foundry工具链进行构建、测试和部署。

## 开发环境设置

### 前置要求

- 安装Foundry工具链 (forge, cast, anvil, chisel)
- Solidity ^0.8.13

### 安装依赖

```shell
forge install
```

## 构建命令

### 编译合约

```shell
forge build
```

### 代码格式化

```shell
forge fmt
```

### 生成Gas快照

```shell
forge snapshot
```

## 测试指南

### 运行所有测试

```shell
forge test
```

### 运行详细测试输出

```shell
forge test -vvv
```

### 运行特定测试

```shell
forge test --match-test test_Increment
```

### 运行模糊测试

项目包含模糊测试,使用`testFuzz_`前缀命名的测试函数会自动进行模糊测试。

### Gas报告

```shell
forge test --gas-report
```

## 代码规范

### Solidity风格

- 使用SPDX许可证标识符: `// SPDX-License-Identifier: UNLICENSED`
- Solidity版本: `pragma solidity ^0.8.13;`
- 遵循Solidity官方风格指南
- 使用驼峰命名法命名函数和变量
- 使用帕斯卡命名法命名合约
- 公共状态变量应有明确的可见性修饰符

### 测试规范

- 测试合约命名: `<ContractName>Test`
- 测试函数前缀: `test_` (标准测试) 或 `testFuzz_` (模糊测试)
- 每个测试合约必须包含`setUp()`函数进行初始化
- 使用forge-std的断言函数 (assertEq, assertTrue等)
- 测试文件位置: `test/` 目录

### 项目结构

```
src/          - 智能合约源代码
test/         - 测试文件
script/       - 部署脚本
lib/          - 依赖库 (通过forge install安装)
out/          - 编译输出 (自动生成)
```

## 部署指南

### 本地测试网部署

1. 启动本地节点:
```shell
anvil
```

2. 部署合约:
```shell
forge script script/Counter.s.sol:CounterScript --rpc-url http://localhost:8545 --private-key <private_key> --broadcast
```

### 主网/测试网部署

```shell
forge script script/Counter.s.sol:CounterScript --rpc-url <rpc_url> --private-key <private_key> --broadcast --verify
```

## 安全注意事项

- 永远不要在代码中硬编码私钥
- 使用环境变量或加密的密钥管理工具存储敏感信息
- 部署前必须运行完整的测试套件
- 对于生产环境合约,建议进行专业的安全审计
- 使用`forge coverage`检查测试覆盖率
- 注意整数溢出/下溢 (虽然Solidity 0.8+有内置保护)
- 谨慎处理外部调用和重入攻击

## 常用工具

### Cast - 与合约交互

```shell
# 调用只读函数
cast call <contract_address> "number()(uint256)" --rpc-url <rpc_url>

# 发送交易
cast send <contract_address> "setNumber(uint256)" <value> --rpc-url <rpc_url> --private-key <private_key>

# 查询区块链数据
cast block-number --rpc-url <rpc_url>
```

### Chisel - Solidity REPL

```shell
chisel
```

在REPL中可以快速测试Solidity代码片段。

## 调试技巧

- 使用`console.log`进行调试 (需要导入`forge-std/console.sol`)
- 使用`forge test -vvvv`查看详细的调用栈
- 使用`forge debug <test_name>`进入交互式调试器
- 检查`foundry.toml`配置文件确保设置正确

## 文档资源

- Foundry Book: https://book.getfoundry.sh/
- Solidity文档: https://docs.soliditylang.org/
- forge-std库: https://github.com/foundry-rs/forge-std

## 提交规范

- 提交前必须运行`forge test`确保所有测试通过
- 提交前运行`forge fmt`格式化代码
- 提交信息使用清晰的中文描述
- 对于合约修改,必须更新或添加相应的测试

