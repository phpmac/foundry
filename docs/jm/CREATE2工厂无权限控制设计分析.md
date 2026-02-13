# CREATE2 工厂无权限控制设计分析

## 结论

CREATE2 工厂合约不设 access control 是**业界标准做法**, 不是安全疏漏.

## 核心原理

CREATE2 地址由以下公式决定:

```
address = keccak256(0xff + factory + salt + keccak256(initCode))[12:]
```

四个输入中, `0xff` 是常量, `factory` 是工厂地址, 只有 `salt` 和 `initCode` 可变. 这意味着:

- **地址完全由参数决定, 与调用者无关** - 任何人用同样的 salt + initCode 都会得到同一个地址
- **同一 salt + initCode 只能部署一次** - 第二次部署会 revert
- **不同 salt 产生不同地址** - 不会互相干扰

因此, 加 `onlyOwner` 不仅无意义, 反而引入了额外的状态变量和攻击面.

## 业界实例

### 1. Deterministic Deployment Proxy (Nick Johnson)

- 地址: `0x4e59b44847b379578588920ca78fbf26c0b4956c`
- 作者: Nick Johnson (ENS 创始人)
- 仓库: https://github.com/Arachnid/deterministic-deployment-proxy
- **完全无权限控制**, 任何人可调用
- Foundry 默认的 CREATE2 deployer
- 已部署到几乎所有 EVM 链

代理合约核心逻辑极简 - 接收 `salt(32 bytes) + initCode` 作为 calldata, 直接执行 CREATE2, 无任何权限检查.

### 2. OpenZeppelin Create2 Library

- 仓库: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Create2.sol
- 版本: v5.5.0
- **`deploy()` 函数是 `internal`**, 无权限修饰符
- 只做三件事: 检查余额, 检查 bytecode 非空, 执行 CREATE2

```solidity
function deploy(uint256 amount, bytes32 salt, bytes memory bytecode)
    internal returns (address addr)
{
    // 检查余额
    // 检查 bytecode 非空
    // 执行 CREATE2
    // 检查部署成功
}
```

OpenZeppelin 作为安全审计领域的权威, 其 Create2 library **没有任何 access control**.

### 3. Uniswap V2 Factory

- `createPair()` 函数**完全 permissionless** - 任何人可创建交易对
- 使用 CREATE2 部署 pair 合约, salt 为 `keccak256(abi.encodePacked(token0, token1))`
- Init code hash: `0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f`
- 这使得 pair 地址可离线计算, 无需链上查询

### 4. ERC-2470: Singleton Factory

- EIP: https://eips.ethereum.org/EIPS/eip-2470
- 以太坊官方标准, 定义了 CREATE2 单例工厂的规范
- 使用 Nick's Method 部署, **permissionless by design**

### 5. ERC-7955: Permissionless CREATE2 Factory (2025)

- EIP: https://eips.ethereum.org/EIPS/eip-7955
- 最新标准 (2025-05, Draft)
- 工厂地址: `0xC0DEb853af168215879d284cc8B4d0A645fA9b0E`
- 使用 EIP-7702 部署, 解决了 Nick's Method 的局限性
- 标题直接就叫 **"Permissionless"** - 无权限是核心设计目标

ERC-7955 明确指出:

> "Once deployed, any user can call the CREATE2 factory to deploy new contracts
> deterministically across multiple EVM chains **without permission checks**
> or key-based authentication."

## 安全分析: 为什么不需要权限控制

### 不存在的威胁

| 攻击场景 | 是否有效 | 原因 |
|----------|---------|------|
| 别人抢先部署你的合约 | 无影响 | 合约部署到同一地址, 构造函数参数决定 owner |
| 别人用你的 salt | 无影响 | 不同 initCode 产生不同地址 |
| 恶意部署垃圾合约 | 无影响 | 不会占用你的地址 (salt/initCode 不同) |
| DOS 工厂合约 | 不可能 | 工厂无状态, 无法被 DOS |

### 唯一风险: Front-running

攻击者监控 mempool, 看到你的交易后抢先提交相同参数. 但:

1. 结果是**同一个合约被部署到同一个地址** - 合约逻辑和 owner 由 initCode 决定
2. 你的交易会 revert (合约已存在), 但**你的合约已经部署好了** - 目的达成
3. 攻击者只是帮你付了 gas 费

如 ERC-7955 所述:

> "An attacker can only delay the deployment... but not permanently prevent it
> from happening. The damage is limited to gas griefing."

### 加 onlyOwner 反而有害

1. **增加攻击面** - 多了 owner 状态变量, 可能被钓鱼/社工转移
2. **违反 CREATE2 确定性原则** - 工厂的可用性依赖于 owner 的可用性
3. **增加部署成本** - 多余的 storage 读写消耗 gas
4. **破坏跨链一致性** - 不同链上的 owner 需要协调

## 参考链接

| 资源 | 链接 |
|------|------|
| EIP-1014: CREATE2 | https://eips.ethereum.org/EIPS/eip-1014 |
| ERC-2470: Singleton Factory | https://eips.ethereum.org/EIPS/eip-2470 |
| ERC-7955: Permissionless CREATE2 Factory | https://eips.ethereum.org/EIPS/eip-7955 |
| Nick's Deterministic Deployment Proxy | https://github.com/Arachnid/deterministic-deployment-proxy |
| OpenZeppelin Create2 Library | https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Create2.sol |
| Foundry CREATE2 Deployment Guide | https://book.getfoundry.sh/guides/deterministic-deployments-using-create2 |
| OpenZeppelin Blog: Getting the Most out of CREATE2 | https://blog.openzeppelin.com/getting-the-most-out-of-create2 |
| Safe Global: Meet ERC-7955 | https://safe.global/blog/safe-research-meet-erc-7955-no-private-key-required |
