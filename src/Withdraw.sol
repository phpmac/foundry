// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

/**
 * 提现合约
 * 前端代码参考在 https://github.com/phpmac/laravel/blob/etf2/resources/js/components/WithdrawModal.tsx
 * ! 使用 过期时间+唯一网络id 防止重放攻击
 *
 * 部署流程(可执行todo):
 * 1.提现地址需要approve代币
 */
contract Withdraw is AccessControlUpgradeable, EIP712Upgradeable {
    using ECDSA for bytes32;

    // 提现事件: 提现地址,nonce,提现代币地址,提现金额
    event Withdrawal(
        address indexed account,
        uint256 indexed nonce,
        address indexed tokenAddress,
        uint256 withdrawalAmount
    );

    bool public isPause; // 是否暂停

    address public withdrawalSignAddress; // 签名地址

    mapping(address account => uint256) public withdrawTime; // 提现时间
    mapping(address account => uint256) public accountNonce; // 账户nonce
    mapping(address account => mapping(uint256 => bool)) public nonceStatus; // nonce状态

    address public withdrawAddress; // 提现出金地址

    modifier onlyNotPause() {
        require(!isPause, "Withdrawal: is pause");
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

    /**
     * 初始化合约
     * @param _withdrawalSignAddress 签名地址
     */
    function initialize(address _withdrawalSignAddress) public initializer {
        __AccessControl_init();
        __EIP712_init("Withdraw", "1");

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        setPause(false);
        setWithdrawalSignAddress(_withdrawalSignAddress);
    }

    /**
     * 内部提现
     * @param _account 提现账户地址
     * @param _amount 提现金额
     * @param _withdrawalToken 提现代币地址
     * @param _signNonce 签名nonce
     */
    function _withdrawal(
        address _account,
        uint256 _amount,
        address _withdrawalToken,
        uint256 _signNonce
    ) internal {
        IERC20 withdrawalToken = IERC20(_withdrawalToken);

        withdrawTime[_account] = block.timestamp;

        require(withdrawAddress != address(0), "withdraw address is not set");

        // 如果钱足够就使用本地余额直接转账
        if (withdrawalToken.balanceOf(address(this)) >= _amount) {
            require(
                withdrawalToken.transfer(_account, _amount),
                "transfer failed"
            );
        } else {
            require(
                withdrawalToken.balanceOf(withdrawAddress) >= _amount,
                "balance not enough"
            );
            require(
                withdrawalToken.allowance(withdrawAddress, address(this)) >=
                    _amount,
                "allowance not enough"
            );
            require(
                withdrawalToken.transferFrom(
                    withdrawAddress,
                    _account,
                    _amount
                ),
                "transfer failed"
            );
        }

        emit Withdrawal(_account, _signNonce, _withdrawalToken, _amount);
    }

    /**
     * 提现
     * @param _amount 提现金额
     * @param _withdrawalToken 提现代币地址
     * @param _signNonce 签名nonce
     * @param _deadline 签名过期时间
     * @param _signature 签名数据
     */
    function withdrawal(
        uint256 _amount,
        address _withdrawalToken,
        uint256 _signNonce,
        uint256 _deadline,
        bytes memory _signature
    ) public onlyNotPause onlyEOA {
        require(block.timestamp <= _deadline, "signature expired");
        address account = _msgSender();
        require(_amount > 0, "amount must be greater than zero");
        require(
            withdrawTime[account] + 1 seconds < block.timestamp,
            "multiple withdrawals are not allowed within 1 second"
        );
        require(!nonceStatus[account][_signNonce], "nonce is already exists");
        nonceStatus[account][_signNonce] = true;
        accountNonce[account]++;
        (bytes32 message, ) = getSignNonceMessage(
            _signNonce,
            account,
            _amount,
            _withdrawalToken,
            _deadline
        );
        require(_verify(message, _signature), "invalid signature");

        _withdrawal(account, _amount, _withdrawalToken, _signNonce);
    }

    /**
     * 获取签名数据
     * @param _withdrawalToken 提现代币地址
     * @param _amount 提现金额
     * @param _account 提现账户地址
     * @return signMessage 签名消息
     * @return signNonce 签名nonce
     */
    function getSignMessage(
        address _withdrawalToken,
        uint256 _amount,
        address _account
    ) public view returns (bytes32 signMessage, uint256 signNonce) {
        signNonce = accountNonce[_account];
        return
            getSignNonceMessage(
                signNonce,
                _account,
                _amount,
                _withdrawalToken,
                0
            );
    }

    /**
     * 获取签名数据
     * @param _nonce 签名nonce
     * @param _from 提现账户地址
     * @param _amount 提现金额
     * @param _withdrawalToken 提现代币地址
     * @param _deadline 签名过期时间
     * @return signMessage 签名消息
     * @return signNonce 签名nonce
     */
    function getSignNonceMessage(
        uint256 _nonce,
        address _from,
        uint256 _amount,
        address _withdrawalToken,
        uint256 _deadline
    ) public view returns (bytes32 signMessage, uint256 signNonce) {
        bytes32 STACKING_HASH = keccak256(
            "Withdrawal(uint256 nonce,address from,uint256 amount,address token,uint256 deadline,uint256 chainId)"
        );
        bytes32 hash = keccak256(
            abi.encode(
                STACKING_HASH,
                _nonce,
                _from,
                _amount,
                _withdrawalToken,
                _deadline,
                block.chainid
            )
        );
        signMessage = _hashTypedDataV4(hash);
        signNonce = _nonce;
    }

    /**
     * 验证签名
     * @param _digest 签名消息
     * @param _signature 签名数据
     * @return bool 是否验证通过
     */
    function _verify(
        bytes32 _digest,
        bytes memory _signature
    ) internal view returns (bool) {
        require(_signature.length == 65, "invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }
        require(
            uint256(s) <=
                0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "invalid s value"
        );
        address signer = _digest.recover(v, r, s);
        return signer == withdrawalSignAddress;
    }

    /**
     * 管理员设置签名地址
     * @param _withdrawalSignAddress 签名地址
     */
    function setWithdrawalSignAddress(
        address _withdrawalSignAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _withdrawalSignAddress != address(0),
            "withdrawal sign address is not set"
        );
        withdrawalSignAddress = _withdrawalSignAddress;
    }

    /**
     * 管理员设置提现出金地址
     * @param _withdrawAddress 提现出金地址
     */
    function setWithdrawAddress(
        address _withdrawAddress
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_withdrawAddress != address(0), "withdraw address is not set");
        withdrawAddress = _withdrawAddress;
    }

    /**
     * 管理员设置暂停
     * @param _isPause 是否暂停
     */
    function setPause(bool _isPause) public onlyRole(DEFAULT_ADMIN_ROLE) {
        isPause = _isPause;
    }

    /**
     * 管理员执行自动化配置
     * ! 有一些不能写在里面,比如随时改动的手续费,只能写入固定的,或者判断没有初始化再初始化
     */
    function todo() public onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * 健康检查
     */
    function healthcheck() public view onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            withdrawalSignAddress != address(0),
            "withdrawal address is not set"
        );
    }
}
