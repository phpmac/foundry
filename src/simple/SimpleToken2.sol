// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * 简单代币
 *
 */
contract SimpleToken2 is ERC20Upgradeable, AccessControlUpgradeable {
    // 允许的测试网ID
    uint256[] public allowTestChainId;

    mapping(address => uint256) private _lastTradeBlock; // 记录用户最后一次交易的区块号
    mapping(address => bool) public automatedMarketMakerPairs; // 自动做市商(AMM)交易对地址列表

    // 是否在允许的测试网
    modifier onlyTestChain() {
        require(isAllowTestChainId(), "Not testnet");
        _;
    }

    // ! 只允许EOA调用,防止合约调用导致的攻击,例如闪电贷
    modifier onlyEOA() {
        require(tx.origin == _msgSender(), "EOA");
        _;
    }

    /**
     * ! 禁用实现合约的初始化, 防止攻击者直接初始化实现合约
     * 参考: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable#initializing_the_implementation_contract
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _amount
    ) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        __ERC20_init(_name, _symbol);

        _mint(_msgSender(), _amount);

        addAllTestChain();

        todo();
    }

    /**
     * 管理员批量添加测试网ID
     * @param _chainIds 链ID数组
     */
    function addTestChain(
        uint256[] memory _chainIds
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < _chainIds.length; i++) {
            allowTestChainId.push(_chainIds[i]);
        }
    }

    /**
     * 管理员批量铸造
     * @param _to 铸造地址
     * @param _amount 铸造数量
     */
    function batchMint(
        address[] memory _to,
        uint256[] memory _amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_to.length == _amount.length, "to and amount length mismatch");
        for (uint256 i = 0; i < _to.length; i++) {
            _mint(_to[i], _amount[i]);
        }
    }

    /**
     * 仅测试网免费铸造代币
     * @param _amount 铸造数量
     */
    function freeMint(uint256 _amount) public onlyTestChain {
        // ! 添加数量限制，防止滥用
        require(
            _amount > 0 && _amount <= 1000 * 10 ** decimals(),
            "Invalid mint amount"
        );
        _mint(_msgSender(), _amount);
    }

    /**
     * 是否在允许的测试网
     * @return 是否在允许的测试网
     */
    function isAllowTestChainId() public view returns (bool) {
        for (uint256 i = 0; i < allowTestChainId.length; i++) {
            if (allowTestChainId[i] == block.chainid) {
                return true;
            }
        }
        return false;
    }

    /**
     * 管理员添加所有测试网ID
     */
    function addAllTestChain() public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 97;
        chainIds[1] = 42161;
        addTestChain(chainIds);
    }

    /**
     * @dev 设置或取消自动做市商(AMM)的交易对地址.
     * @param _pair 交易对地址.
     * @param _isPair 是否为交易对. true为是, false为否.
     */
    function setAutomatedMarketMakerPair(
        address _pair,
        bool _isPair
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        automatedMarketMakerPairs[_pair] = _isPair;
    }

    /**
     * ! 在代币转移、铸造或销毁时调用的钩子函数.
     * 重写此函数以实现反闪电贷逻辑.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        // 检查交易是否涉及已知的AMM交易对
        bool isSwap = automatedMarketMakerPairs[from] ||
            automatedMarketMakerPairs[to];

        // TODO 缺少三明治攻击

        // ========== Checks - 先验证条件 ==========
        if (isSwap) {
            // ! 使用 tx.origin 而不是 from/to, 防止合约中转绕过
            require(
                _lastTradeBlock[tx.origin] != block.number,
                "AntiFlashLoan: Cannot trade more than once in the same block."
            );

            // ========== Effects - 修改状态 ==========
            _lastTradeBlock[tx.origin] = block.number;
        }

        // 检查交易是否涉及已知的AMM交易对
        bool isBuy = automatedMarketMakerPairs[from] && to != address(0);
        bool isSell = automatedMarketMakerPairs[to] && from != address(0);

        // ========== Interactions - 执行转账 ==========
        super._update(from, to, value);
    }

    /**
     * 管理员执行自动化配置
     * ! 有一些不能写在里面,比如随时改动的手续费,只能写入固定的,或者判断没有初始化再初始化
     */
    function todo() public onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * 健康检查
     */
    function healthcheck() public view {}
}
