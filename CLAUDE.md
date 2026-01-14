# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 核心原则与安全工作流

- 合约开发和漏洞研究, 从普通用户角度审计
- 数值表示: `1e18` 用 `ether`, `30 * 1e18` 用 `30 ether`
- 重点防护: 闪电贷攻击, 数字溢出, 重入攻击
- 不重复编写已有方法

### 当前研究课题
- EIP-7702: 验证 EOA 升级为智能合约后, 结合重入+质押的攻击可行性


1. **审计流程**: 一般执行命令 `slither 指定合约` 静态审计指定合约文件, 再进行综合分析是否存在漏洞.
2. **漏洞研究**: 可以使用 `exa` mcp工具对框架进行最新漏洞查询, 和确认漏洞是否存在.
3. **中文日志**: 编写单元测试的 `console` 输出必须写中文 (需要使用 `unicode` 编码),例如 `console.log(unicode"中文")`
4. **格式规范**: 除 `console` 日志外, 所有代码和文档中的标点符号必须使用**英文半角标点**.
5. **数学公式**: 文档和回复中的数学公式应避免使用 LaTeX 格式 (如 `\times`, `\text{}`), 统一使用易读的纯文本或代码格式 (如 `*`, `^`, `/`), 确保在终端中清晰可见.
6. **可视化**: 如果任务要求, 可以在 `docs/` 目录下画出对应的流程图, 确保链路保持清晰.
7. **回复规范**: 在终端命令行中回复应保持简洁. 如果输出内容较多或具有存档价值 (如详细分析, 报告等), 应整理成 `.md` 文档存放在 `docs/` 目录下, 并在终端提供简短摘要和文件路径.

## 漏洞研究规范 (参考 overflow 目录)

当收集或研究新漏洞时, 必须遵循以下结构进行归档:

### 1. 漏洞原理说明 (`docs/`)
- 路径: `docs/<vulnerability_type>/<name>原理.md`
- 内容: 包含漏洞定义, 数学原理, **攻击流程图**, 防御方案及测试验证说明.
- 参考: `docs/overflow/溢出攻击原理.md`

### 2. 漏洞逻辑摘要与技能库 (`.claude/skills/`)
- **严格遵循规范**: 对 `.claude/skills/` 目录的任何更新 (包括 `SKILL.md` 和资源文件) 必须严格遵循 Claude Skills 的定义规范 (包括 YAML frontmatter, 结构化描述等).
- 在 `.claude/skills/vulnerability-checklist/resources/` 对应的类别文件中更新漏洞逻辑摘要, 风险等级和检测方法.

### 3. 合约代码 (`src/`)
- 路径: `src/<vulnerability_type>/`
- 内容: 包含漏洞合约 (如 `Vulnerable*.sol`) 和修复后的合约 (如 `Safe*.sol`).

### 4. 单元测试与 PoC (`test/`)
- 路径: `test/<vulnerability_type>/`
- 内容: 包含分步详解测试 (如 `*Explain.t.sol`) 和攻击演示测试 (如 `*Attack.t.sol`).

## 开发命令

### 编译与构建
- 编译合约: `forge build`
- 离线编译: `forge build --offline`

### 测试 (Foundry)
- 运行所有测试: `forge test`
- **离线测试 (推荐)**: `forge test --offline`
- 离线运行指定测试并显示详细日志: `forge test --match-test testFunctionName -vvv --offline`
- 运行指定文件: `forge test --match-path test/path/to/test.t.sol --offline`
- 显示 Gas 报告: `forge test --gas-report`

### 脚本与部署
- 离线执行脚本: `forge script script/PathToScript.s.sol --offline`

## 代码架构

- `src/`: 智能合约源代码, 按漏洞类型子目录存放.
- `test/`: 测试合约和漏洞复现 (PoC) 代码, 按漏洞类型子目录存放.
- `script/`: 部署或自动化交互脚本.
- `docs/`: 存放漏洞原理说明文档和流程图.
- `.claude/skills/`: 存放安全审计检查清单等自定义技能资源, 必须符合 Skills 开发规范.
