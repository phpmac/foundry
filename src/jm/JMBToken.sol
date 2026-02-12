// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title JMB Token
 * @dev LP分红凭证代币
 */
contract JMBToken is ERC20, Ownable {
    // 允许执行mint和burn的业务合约地址.
    address public minter;

    event MinterUpdated(address minter);

    error OnlyMinter();
    error NonTransferable();
    error InvalidAddress();

    // 初始化凭证名称和管理员.
    constructor() ERC20("JM Bonus", "JMB") Ownable(msg.sender) {}

    // 限制仅minter可调用的函数.
    modifier onlyMinter() {
        if (msg.sender != minter) revert OnlyMinter();
        _;
    }

    // owner设置minter, 防止误设为零地址.
    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert InvalidAddress();
        minter = _minter;
        emit MinterUpdated(_minter);
    }

    // 按业务需要铸造JMB凭证.
    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    // 用户解除LP关系时销毁对应JMB凭证.
    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }

    // 禁止授权, 防止JMB作为可流通代币被转移.
    function approve(
        address spender,
        uint256 amount
    ) public pure override returns (bool) {
        spender;
        amount;
        revert NonTransferable();
    }

    // 禁止直接转账, JMB仅作为不可转让凭证使用.
    function transfer(
        address to,
        uint256 amount
    ) public pure override returns (bool) {
        to;
        amount;
        revert NonTransferable();
    }

    // 禁止代理转账, 避免绕过transfer限制.
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public pure override returns (bool) {
        from;
        to;
        amount;
        revert NonTransferable();
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // 仅允许铸造和销毁, 禁止用户间转账
        if (from != address(0) && to != address(0)) revert NonTransferable();
        super._update(from, to, value);
    }
}
