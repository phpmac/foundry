---
name: env-config-standard
description: Use when 用户提到 source .env 很麻烦, 不想手动传 --rpc-url/--private-key/--etherscan-api-key, 或要统一部署与验证命令
---

# 环境变量配置规范

## 目标

- 让部署与验证命令尽量短, 避免反复手动传参数.
- 配置集中在 `foundry.toml` 和 `.env`, 减少误操作.
- 敏感信息不写死在仓库文件中.

## 适用场景

- 用户说不想每次 `source .env`.
- 用户说不想手动写 `--rpc-url` 或 `--etherscan-api-key`.
- 用户希望团队项目统一命令格式.

## 标准做法

### 1) `foundry.toml` 固定公共配置

在 `foundry.toml` 中配置:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
eth_rpc_url = "https://bsc-dataseed.binance.org"

[rpc_endpoints]
bsc_mainnet = "https://bsc-dataseed.binance.org"

[etherscan]
bsc = { key = "${BSCSCAN_API_KEY}" }
```

说明:
- `eth_rpc_url` 用于默认 RPC.
- `[rpc_endpoints]` 用于多链命名端点管理.
- `[etherscan]` 使用环境变量引用 key, 不明文写死.

### 2) `.env` 仅放敏感信息

推荐保留:

```bash
PRIVATE_KEY=0x...
BSCSCAN_API_KEY=...
VANITY_SALT=0x...
```

禁止:
- 把真实 key 直接写进 `foundry.toml`.
- 在文档示例里粘贴真实私钥或真实 API key.

### 3) 命令规范

部署命令优先:

```bash
forge script script/xxx.s.sol --broadcast
```

验证命令优先:

```bash
forge verify-contract <address> <path:contract> --chain bsc --watch
```

避免长期使用:

```bash
--rpc-url ...
--etherscan-api-key ...
```

这些参数仅在临时排障时使用.

## 快速检查清单

- [ ] `foundry.toml` 有 `eth_rpc_url`.
- [ ] `foundry.toml` 有 `[rpc_endpoints]`.
- [ ] `foundry.toml` 有 `[etherscan]` 且 key 使用 `${VAR}` 引用.
- [ ] `.env` 包含 `PRIVATE_KEY` 与 `BSCSCAN_API_KEY`.
- [ ] 文档命令未强依赖 `source .env`.
- [ ] 文档未出现明文私钥/API key.

## 常见问题

### Q1: 还是提示 RPC 未设置

排查顺序:
1. 检查 `foundry.toml` 是否在项目根目录.
2. 检查 `[profile.default]` 下是否有 `eth_rpc_url`.
3. 临时加 `--rpc-url` 验证是否为配置读取问题.

### Q2: 验证时报 key 相关错误

排查顺序:
1. 检查 `.env` 是否存在 `BSCSCAN_API_KEY`.
2. 检查 `foundry.toml` 中是否为 `${BSCSCAN_API_KEY}`.
3. 检查 `--chain` 是否与 `[etherscan]` 键名一致 (如 `bsc`).

### Q3: 团队里有人喜欢全命令参数风格

建议:
- 文档主流程使用简洁命令.
- 额外提供一个“排障命令”小节, 保留带参数版本.
