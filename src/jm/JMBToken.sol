// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title JMB Token
 * @dev LP分红凭证代币
 */
contract JMBToken is ERC20, Ownable {
    // 允许铸造的合约地址(LPDistributor)
    address public minter;

    event MinterUpdated(address minter);

    constructor() ERC20("JM Bonus", "JMB") Ownable(msg.sender) {}

    modifier onlyMinter() {
        require(msg.sender == minter, "Only minter");
        _;
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit MinterUpdated(_minter);
    }

    function mint(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
