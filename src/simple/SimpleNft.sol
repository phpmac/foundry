// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * 简单的nft
 *
 */
contract SimpleNft is AccessControlUpgradeable, ERC721EnumerableUpgradeable {
    uint256 public id; // 当前id

    // 允许的测试网ID
    uint256[] public allowTestChainId;

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
        string memory _symbol
    ) public initializer {
        __AccessControl_init();
        __ERC721_init(_name, _symbol);

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        // 添加BSC测试网
        allowTestChainId.push(97);

        todo();
    }

    /**
     * 生产矿机
     * @param to 地址
     */
    function mint(address to) private {
        ++id;

        _safeMint(to, id);
    }

    /**
     * 管理员批量生产矿机
     * @param _users 地址
     * @param _amunts 数量
     */
    function batchMint(
        address[] memory _users,
        uint256[] memory _amunts
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _users.length == _amunts.length,
            "ZulongNft: users and amunts length mismatch"
        );

        for (uint256 i = 0; i < _users.length; i++) {
            for (uint256 j = 0; j < _amunts[i]; j++) {
                mint(_users[i]);
            }
        }
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
     * 仅测试网免费铸造NFT
     * @param _amount 铸造数量
     */
    function freeMint(uint256 _amount) public onlyTestChain {
        for (uint256 i = 0; i < _amount; i++) {
            mint(_msgSender());
        }
    }

    // 是否在允许的测试网
    function isAllowTestChainId() public view returns (bool) {
        for (uint256 i = 0; i < allowTestChainId.length; i++) {
            if (allowTestChainId[i] == block.chainid) {
                return true;
            }
        }
        return false;
    }

    /**
     * 支持接口
     * @param interfaceId 接口id
     * @return 是否支持
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
     * 管理员执行自动化配置
     * ! 有一些不能写在里面,比如随时改动的手续费,只能写入固定的,或者判断没有初始化再初始化
     */
    function todo() public onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * 健康检查
     */
    function healthcheck() public view {}
}
