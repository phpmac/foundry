# CREATE2 无权限控制安全补充

> 来源整理: `docs/jm/CREATE2工厂无权限控制设计分析.md`
> 用途: 作为 `create2-vanity-deploy` 的附加安全参考, 不放入 `SKILL.md` 主体.

## 核心结论

- CREATE2 工厂不加 access control 是行业通用设计.
- 地址由 `deployer + salt + initCodeHash` 决定, 与调用者身份无关.
- `same salt + same initCode` 只能部署一次.

## 为什么通常不加 onlyOwner

- 不提升地址可控性: 地址是否命中靓号只由参数决定.
- 增加复杂度: 多 owner 状态与权限逻辑, 增加维护和攻击面.
- 破坏通用性: permissionless 工厂更利于跨链和公共基础设施复用.

## 风险边界

### 1) Front-running

- 攻击者可抢先提交相同参数.
- 结果通常是同一地址被部署相同代码, 主要影响是 gas 竞争, 不是地址所有权被劫持.

### 2) 参数漂移风险

- 代码改动或构造参数变化会导致 `initCodeHash` 变化.
- 之前算出的 salt 可能失效, 需要重新搜索.

## 实操建议

- 搜索 salt 前, 固化编译版本和构造参数.
- 将搜索和部署流程脚本化, 避免手工参数错误.
- 部署后立刻记录:
  - deployer 地址
  - salt
  - initCodeHash
  - 最终合约地址

## 参考标准与实现

- EIP-1014 (CREATE2): https://eips.ethereum.org/EIPS/eip-1014
- ERC-2470 (Singleton Factory): https://eips.ethereum.org/EIPS/eip-2470
- ERC-7955 (Permissionless CREATE2 Factory): https://eips.ethereum.org/EIPS/eip-7955
- Arachnid Deterministic Deployment Proxy: https://github.com/Arachnid/deterministic-deployment-proxy
- OpenZeppelin Create2: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Create2.sol
