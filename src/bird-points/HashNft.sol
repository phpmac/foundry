// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title HashNft
 * @dev 算力 NFT 合约 (可升级)
 *
 * 功能:
 * 1. 代表用户购买的算力
 * 2. 支持 ERC721 标准的转赠功能
 * 3. MINTER_ROLE 角色可以铸造 NFT
 */
contract HashNft is
    AccessControlUpgradeable,
    ERC721EnumerableUpgradeable,
    UUPSUpgradeable
{
    // 角色常量
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public currentId; // 当前 tokenId

    /**
     * ! 禁用实现合约的初始化, 防止攻击者直接初始化实现合约
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * UUPS 升级授权
     * @param newImplementation 新实现合约地址
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * 初始化
     * @param _name NFT 名称
     * @param _symbol NFT 符号
     */
    function initialize(
        string memory _name,
        string memory _symbol
    ) public initializer {
        __AccessControl_init();
        __ERC721_init(_name, _symbol);

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
    }

    /**
     * 铸造 NFT (需要 MINTER_ROLE 权限)
     * @param to 接收地址
     */
    function mint(address to) external onlyRole(MINTER_ROLE) {
        currentId++;
        _safeMint(to, currentId);
    }

    /**
     * 批量铸造 NFT (需要 MINTER_ROLE 权限)
     * @param to 接收地址
     * @param amount 数量
     */
    function mintBatch(
        address to,
        uint256 amount
    ) external onlyRole(MINTER_ROLE) {
        for (uint256 i = 0; i < amount; i++) {
            currentId++;
            _safeMint(to, currentId);
        }
    }

    /**
     * 支持接口
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * 健康检查
     */
    function healthcheck() public view {}
}
