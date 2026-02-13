---
name: create2-vanity-deploy
description: 使用 Foundry CREATE2 生成靓号合约地址并部署. 当用户提到靓号地址, 0x1111/8888 前后缀, cast create2, CREATE2 部署脚本, 或 CREATE2 单元测试时使用.
---

# CREATE2 靓号部署技能

## 用途

用于在 Foundry 项目里快速完成:
- 靓号 salt 搜索
- CREATE2 部署脚本编写
- 单元测试验证
- 合约验证命令

## 标准流程

1. 计算目标合约 `init code` (默认示例用 `Counter`):

```bash
forge inspect Counter bytecode
```

2. 搜索靓号 salt (推荐 `cast create2`):

```bash
# 后缀
cast create2 --ends-with 1111 --init-code $(forge inspect Counter bytecode)

# 前缀
cast create2 --starts-with 8888 --init-code $(forge inspect Counter bytecode)

# 任意位置
cast create2 --matching 8888 --init-code $(forge inspect Counter bytecode)
```

3. 将 `Salt` 写入 `.env`:

```bash
VANITY_SALT=0x...
```

4. 执行部署脚本:

```bash
forge script script/jm/DeployVanity.s.sol --broadcast
```

5. 验证合约:

```bash
forge verify-contract <address> src/Counter.sol:Counter --chain bsc --watch
```

## 脚本模板

见: [resources/deploy-script-template.md](resources/deploy-script-template.md)

## 单元测试模板

见: [resources/create2-vanity-test-template.md](resources/create2-vanity-test-template.md)

## 注意事项

- `target` 写 `0x8888` 才表示十六进制后缀 `...8888`, 写 `8888` 是十进制 `0x22b8`.
- `new Contract{salt: s}()` 默认做后缀匹配更简单.
- 前缀/任意匹配优先用 `cast create2`, 不建议在 Solidity 测试里做复杂字符串匹配.
- 构造参数会改变 `initCode`, 参数变化后需要重新搜索 salt.
- 当前 skill 的模板以 `Counter` 为示例, 可按同样方式替换为任意合约.
