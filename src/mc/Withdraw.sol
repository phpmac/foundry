// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPancakeRouter} from "./interfaces/IPancakeRouter.sol";

/**
 * 提现合约
 * 前端代码参考在 https://github.com/phpmac/laravel/blob/etf2/resources/js/components/WithdrawModal.tsx
 * ! 使用 过期时间+唯一网络id 防止重放攻击
 *
 * 部署流程(可执行todo):
 * 1.提现地址需要approve代币
 */
contract Withdraw is
    AccessControlUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable
{
    using ECDSA for bytes32;

    // 提现事件: 提现地址,nonce,提现代币地址,提现金额
    event Withdrawal(
        address indexed account,
        uint256 indexed nonce,
        address indexed tokenAddress,
        uint256 withdrawalAmount
    );
    // 手续费事件: 提现地址,手续费总额,买币金额,直接转U金额
    event FeeCharged(
        address indexed account,
        uint256 feeAmount,
        uint256 swapAmount,
        uint256 directAmount
    );

    bool public isPause; // 是否暂停

    address public withdrawalSignAddress; // 签名地址

    mapping(address account => uint256) public withdrawTime; // 提现时间
    mapping(address account => uint256) public accountNonce; // 账户nonce
    mapping(address account => mapping(uint256 => bool)) public nonceStatus; // nonce状态

    address public feeReceiver; // 手续费接收地址(U+买到的币都到这个地址)
    address public pancakeRouter; // PancakeSwap Router地址
    address[] public swapPath; // swap路径, 例如 [USDT, TargetToken]

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
     * @param _feePercent 手续费百分比(0-100), 由签名指定
     * @param _signNonce 签名nonce
     */
    function _withdrawal(
        address _account,
        uint256 _amount,
        address _withdrawalToken,
        uint256 _feePercent,
        uint256 _signNonce
    ) internal {
        IERC20 withdrawalToken = IERC20(_withdrawalToken);

        withdrawTime[_account] = block.timestamp;

        require(
            withdrawalToken.balanceOf(address(this)) >= _amount,
            "balance not enough"
        );

        uint256 userAmount = _amount;

        // 手续费处理
        if (_feePercent > 0 && feeReceiver != address(0)) {
            require(_feePercent <= 100, "fee percent exceeds 100");

            uint256 feeAmount = (_amount * _feePercent) / 100;
            userAmount = _amount - feeAmount;

            uint256 swapAmount = feeAmount / 2; // 50% 买币
            uint256 directAmount = feeAmount - swapAmount; // 50% 直接转U

            // 50% U直接转到feeReceiver
            if (directAmount > 0) {
                require(
                    withdrawalToken.transfer(feeReceiver, directAmount),
                    "fee transfer failed"
                );
            }

            // 50% 通过PancakeSwap买币到feeReceiver
            if (swapAmount > 0) {
                _swapOrTransfer(_withdrawalToken, swapAmount, feeReceiver);
            }

            emit FeeCharged(_account, feeAmount, swapAmount, directAmount);
        }

        require(
            withdrawalToken.transfer(_account, userAmount),
            "transfer failed"
        );

        emit Withdrawal(_account, _signNonce, _withdrawalToken, _amount);
    }

    /**
     * swap买币到_to
     * @param _token 支付代币地址
     * @param _amount swap金额
     * @param _to 接收地址
     */
    function _swapOrTransfer(
        address _token,
        uint256 _amount,
        address _to
    ) internal {
        require(pancakeRouter != address(0), "router not set");
        require(swapPath.length >= 2, "swap path not set");

        IERC20(_token).approve(pancakeRouter, _amount);

        IPancakeRouter(pancakeRouter)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                _amount,
                0,
                swapPath,
                address(this),
                block.timestamp
            );

        // 再把代币转到目标地址
        require(
            IERC20(swapPath[1]).transfer(
                _to,
                IERC20(swapPath[1]).balanceOf(address(this))
            ),
            "transfer failed"
        );
    }

    /**
     * 提现
     * @param _amount 提现金额
     * @param _withdrawalToken 提现代币地址
     * @param _feePercent 手续费百分比(0-100), 由后端签名指定
     * @param _signNonce 签名nonce
     * @param _deadline 签名过期时间
     * @param _signature 签名数据
     */
    function withdrawal(
        uint256 _amount,
        address _withdrawalToken,
        uint256 _feePercent,
        uint256 _signNonce,
        uint256 _deadline,
        bytes memory _signature
    ) public onlyNotPause onlyEOA {
        require(block.timestamp <= _deadline, "signature expired");
        address account = _msgSender();
        require(_amount > 0, "amount must be greater than zero");
        require(
            withdrawTime[account] + 1 minutes < block.timestamp,
            "multiple withdrawals are not allowed within 1 minute"
        );
        require(!nonceStatus[account][_signNonce], "nonce is already exists");
        nonceStatus[account][_signNonce] = true;
        accountNonce[account]++;
        (bytes32 message, ) = getSignNonceMessage(
            _signNonce,
            account,
            _amount,
            _withdrawalToken,
            _feePercent,
            _deadline
        );
        require(_verify(message, _signature), "invalid signature");

        _withdrawal(
            account,
            _amount,
            _withdrawalToken,
            _feePercent,
            _signNonce
        );
    }

    /**
     * 获取签名数据
     * @param _withdrawalToken 提现代币地址
     * @param _amount 提现金额
     * @param _account 提现账户地址
     * @param _feePercent 手续费百分比(0-100)
     * @return signMessage 签名消息
     * @return signNonce 签名nonce
     */
    function getSignMessage(
        address _withdrawalToken,
        uint256 _amount,
        address _account,
        uint256 _feePercent
    ) public view returns (bytes32 signMessage, uint256 signNonce) {
        signNonce = accountNonce[_account];
        return
            getSignNonceMessage(
                signNonce,
                _account,
                _amount,
                _withdrawalToken,
                _feePercent,
                0
            );
    }

    /**
     * 获取签名数据
     * @param _nonce 签名nonce
     * @param _from 提现账户地址
     * @param _amount 提现金额
     * @param _withdrawalToken 提现代币地址
     * @param _feePercent 手续费百分比(0-100)
     * @param _deadline 签名过期时间
     * @return signMessage 签名消息
     * @return signNonce 签名nonce
     */
    function getSignNonceMessage(
        uint256 _nonce,
        address _from,
        uint256 _amount,
        address _withdrawalToken,
        uint256 _feePercent,
        uint256 _deadline
    ) public view returns (bytes32 signMessage, uint256 signNonce) {
        bytes32 STACKING_HASH = keccak256(
            "Withdrawal(uint256 nonce,address from,uint256 amount,address token,uint256 feePercent,uint256 deadline,uint256 chainId)"
        );
        bytes32 hash = keccak256(
            abi.encode(
                STACKING_HASH,
                _nonce,
                _from,
                _amount,
                _withdrawalToken,
                _feePercent,
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
     * 管理员设置暂停
     * @param _isPause 是否暂停
     */
    function setPause(bool _isPause) public onlyRole(DEFAULT_ADMIN_ROLE) {
        isPause = _isPause;
    }

    /**
     * 管理员设置手续费接收地址
     * @param _feeReceiver 手续费接收地址
     */
    function setFeeReceiver(
        address _feeReceiver
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feeReceiver != address(0), "invalid fee receiver");
        feeReceiver = _feeReceiver;
    }

    /**
     * 管理员设置PancakeSwap Router和swap路径
     * @param _router PancakeSwap Router地址
     * @param _path swap路径, 例如 [USDT, TargetToken]
     */
    function setSwapConfig(
        address _router,
        address[] calldata _path
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_router != address(0), "invalid router");
        require(_path.length >= 2, "invalid path");
        pancakeRouter = _router;
        swapPath = _path;
    }

    /**
     * 管理员执行自动化配置
     * ! 有一些不能写在里面,比如随时改动的手续费,只能写入固定的,或者判断没有初始化再初始化
     */
    function todo() public onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * UUPS 升级授权, 仅管理员可调用
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * 健康检查
     */
    function healthcheck() public view {
        require(
            withdrawalSignAddress != address(0),
            "withdrawal address is not set"
        );
        require(feeReceiver != address(0), "fee receiver is not set");
        require(pancakeRouter != address(0), "router is not set");
        require(swapPath.length >= 2, "swap path is not set");
    }
}
