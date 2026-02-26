// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IInvite} from "./interface/IInvite.sol";
import {HashNft} from "./HashNft.sol";

/**
 * @title BuyHashNft
 * @dev NFT算力购买合约 (可升级)
 */
contract BuyHashNft is AccessControlUpgradeable, UUPSUpgradeable {
    uint256 public constant PRICE = 500 ether; // NFT 价格 (18位精度)

    IERC20 public usdt; // USDT 代币合约
    HashNft public nft; // NFT 合约
    IInvite public invite; // 邀请关系合约
    address public treasuryWallet; // 收款钱包地址
    bool public isPaused; // 暂停状态
    uint256 public totalSold; // 总销售数量

    // 购买: 买家, 数量, 总价
    event Bought(address indexed buyer, uint256 amount, uint256 totalPrice);
    // 更新收款钱包: 旧地址, 新地址
    event TreasuryWalletUpdated(
        address indexed oldWallet,
        address indexed newWallet
    );
    // 暂停
    event Paused();
    // 恢复
    event Unpaused();

    modifier onlyEOA() {
        require(tx.origin == _msgSender(), "EOA only");
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "Paused");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function initialize(
        address _usdt, // USDT地址
        address _nft, // NFT地址
        address _invite, // 邀请合约地址
        address _treasury // 收款钱包地址
    ) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        require(_usdt != address(0), "Invalid USDT");
        require(_nft != address(0), "Invalid NFT");
        require(_invite != address(0), "Invalid Invite");
        require(_treasury != address(0), "Invalid Treasury");

        usdt = IERC20(_usdt);
        nft = HashNft(_nft);
        invite = IInvite(_invite);
        treasuryWallet = _treasury;
    }

    /**
     * 购买NFT算力
     * @param _amount 购买数量
     */
    function buy(uint256 _amount) external onlyEOA whenNotPaused {
        require(_amount > 0, "Amount must > 0");

        address buyer = _msgSender();
        require(invite.getParent(buyer) != address(0), "No inviter bound");

        uint256 totalPrice = PRICE * _amount;
        require(
            usdt.transferFrom(buyer, treasuryWallet, totalPrice),
            "USDT transfer failed"
        );

        nft.mintBatch(buyer, _amount);
        totalSold += _amount;

        emit Bought(buyer, _amount, totalPrice);
    }

    /**
     * 设置收款钱包
     * @param _treasury 新地址
     */
    function setTreasuryWallet(
        address _treasury
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasury != address(0), "Invalid address");
        emit TreasuryWalletUpdated(treasuryWallet, _treasury);
        treasuryWallet = _treasury;
    }

    /**
     * 暂停销售
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        isPaused = true;
        emit Paused();
    }

    /**
     * 恢复销售
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        isPaused = false;
        emit Unpaused();
    }

    /**
     * 健康检查
     */
    function healthcheck() public view {
        require(address(usdt) != address(0), "USDT not set");
        require(address(nft) != address(0), "NFT not set");
        require(address(invite) != address(0), "Invite not set");
        require(treasuryWallet != address(0), "Treasury not set");
    }
}
