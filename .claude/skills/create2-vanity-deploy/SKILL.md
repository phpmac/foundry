---
name: create2-vanity-deploy
description: Use when 用户提到靓号地址, 0x1111/8888 前后缀, cast create2, CREATE2 部署脚本, 或 CREATE2 单元测试
---

# CREATE2 靓号部署技能

## 用途

用于在 Foundry 项目里快速完成:
- 靓号 salt 搜索
- CREATE2 部署脚本编写
- 单元测试验证

## 标准流程

```bash
# 1. 搜索 salt
forge script script/<path>/FindVanitySalt.s.sol --offline

# 2. 将输出的 VANITY_SALT 写入 .env

# 3. 测试验证地址一致
forge test --match-path test/<path>/Create2Vanity.t.sol -vvv --offline

# 4. 部署
forge script script/<path>/DeployVanity.s.sol --broadcast
```

## 环境变量配置 (.env)

```bash
# 必需
PRIVATE_KEY=0x...
VANITY_SALT=0x...  # 由 FindVanitySalt 脚本生成

# 可选 (FindVanitySalt 脚本)
VANITY_TARGET=0x1111          # 目标后缀 (默认 0x1111)
VANITY_MAX_ITER=500000        # 最大迭代次数 (默认 500000)
VANITY_MODE=suffix            # suffix(后缀) 或 prefix(前缀)
```

## 核心文件

| 文件 | 用途 |
|------|------|
| `FindVanitySalt.s.sol` | 搜索 salt |
| `DeployVanity.s.sol` | 使用 salt 部署合约 |
| `Create2Vanity.t.sol` | 验证 CREATE2 地址计算 |

## 脚本模板

- [find-salt-script-template.md](resources/find-salt-script-template.md)
- [deploy-script-template.md](resources/deploy-script-template.md)
- [create2-vanity-test-template.md](resources/create2-vanity-test-template.md)

## 注意事项

- `VANITY_TARGET` 写 `0x1111` 表示十六进制后缀 `...1111`, 写 `1111` 是十进制 `0x457`
- 构造参数会改变 `initCode`, 参数变化后需要重新搜索 salt
- 测试和部署必须使用相同的 deployer (PRIVATE_KEY)
- initCode = creationCode + abi.encode(constructor args)

## 安全补充资料

见: [resources/permissionless-security-notes.md](resources/permissionless-security-notes.md)
