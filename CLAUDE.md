# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 核心原则

- 合约开发和漏洞研究, 从普通用户角度审计
- 数值表示: `1e18` 用 `ether`, `30 * 1e18` 用 `30 ether`
- 重点防护: 闪电贷攻击, 数字溢出, 重入攻击

## 代码注释规范

- **变量/状态变量**: 行后注释 `uint256 public total; // 总量`
- **事件**: `// 事件名: 参数说明` 放在事件定义上方
- **函数**: 使用 NatSpec 格式 `/** */` 放在函数定义上方

```solidity
/**
 * 购买 NFT
 * @param _amount 购买数量
 */
function buy(uint256 _amount) external {
```

## 单元测试规范

- 每个合约 3-5 个核心测试用例
- 购买类测试验证: 用户收到资产 / 总量正确 / 收款地址余额正确
- 日志输出: `console.log(unicode"中文说明")`

## 脚本与部署规范

- 禁止硬编码私钥/地址/RPC, 使用环境变量
- Foundry 原生支持 `.env`, 不需要 `export` 或 `source`
- 合约文件只写功能代码, 部署命令放在 `script/` 目录

## 其他规范

- 中文日志使用 `unicode` 编码
- 标点符号使用英文半角
- 回复保持简洁, 详细内容整理到 `docs/`

## 漏洞研究规范

归档结构:
- `docs/<type>/<name>原理.md` - 漏洞原理说明
- `src/<type>/` - 漏洞合约和修复合约
- `test/<type>/` - 单元测试和 PoC

## 开发命令

```bash
forge build --offline                    # 编译
forge test --offline                     # 测试
forge test --match-test testName -vvv    # 指定测试
forge script script/xxx.s.sol --offline  # 脚本
```

## 代码架构

```
src/      # 合约源代码
test/     # 测试和 PoC
script/   # 部署脚本
docs/     # 文档
```