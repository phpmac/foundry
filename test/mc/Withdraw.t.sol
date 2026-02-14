// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Withdraw} from "../../src/mc/Withdraw.sol";

/**
 * 使用链上已部署的提现合约进行 fork 测试
 *
 * forge test --match-path test/mc/Withdraw.t.sol -vvv
 */
contract WithdrawTest is Test {
    Withdraw public withdraw;
    IERC20 public usdt;

    // 链上已部署的代理合约
    address public constant PROXY = 0x61CEFC14ef104F149BF7c80451685F88BE7C14D2;
    address public constant USDT_ADDR =
        0x55d398326f99059fF775485246999027B3197955;
    address public constant ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    // 目标代币
    address public constant MC_TOKEN =
        0xb531613381ccE69DACdfe3693570f8cbf8BDA81f;
    // 合约管理员
    address public constant ADMIN = 0x130151AFa86CD285223f95BBc1e5Aa99eef8B7F2;
    // USDT鲸鱼
    address public constant WHALE = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3;

    uint256 public signerPrivateKey = 0xA11CE;
    address public signer;
    address public alice;

    function setUp() public {
        vm.createSelectFork("bsc_mainnet");

        withdraw = Withdraw(PROXY);
        usdt = IERC20(USDT_ADDR);
        signer = vm.addr(signerPrivateKey);
        alice = makeAddr("alice");

        // ! 健康检查
        withdraw.healthcheck();

        // ! 管理员配置
        vm.startPrank(ADMIN);
        withdraw.setWithdrawalSignAddress(signer);

        // ! 强制设置手续费接收和swap配置 (覆盖链上状态)
        withdraw.setFeeReceiver(0x4f8Db8C9aaDd66E8C107168617346ED86Af4E494);
        address[] memory path = new address[](2);
        path[0] = USDT_ADDR;
        path[1] = MC_TOKEN;
        withdraw.setSwapConfig(ROUTER, path);
        vm.stopPrank();

        // 模拟USDT鲸鱼转账到合约
        vm.prank(WHALE);
        usdt.transfer(PROXY, 1000 ether);

        console.log(unicode"=== 测试环境 ===");
        console.log(unicode"代理合约:", PROXY);
        console.log(unicode"签名地址:", withdraw.withdrawalSignAddress());
        console.log(unicode"手续费接收:", withdraw.feeReceiver());
        console.log(unicode"Router:", withdraw.pancakeRouter());
        console.log(unicode"合约USDT:", usdt.balanceOf(PROXY) / 1e18, "USDT");
    }

    function _sign(
        address _account,
        uint256 _amount,
        address _token,
        uint256 _feePercent,
        uint256 _nonce,
        uint256 _deadline
    ) internal view returns (bytes memory) {
        (bytes32 message, ) = withdraw.getSignNonceMessage(
            _nonce,
            _account,
            _amount,
            _token,
            _feePercent,
            _deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, message);
        return abi.encodePacked(r, s, v);
    }

    /**
     * 格式化输出金额: 整数部分.小数部分(4位)
     */
    function _logAmount(
        string memory label,
        uint256 amount,
        uint8 decimals,
        string memory symbol
    ) internal pure {
        uint256 unit = 10 ** decimals;
        uint256 intPart = amount / unit;
        uint256 fracPart = ((amount % unit) * 10000) / unit; // 保留4位小数
        console.log(
            string.concat(label, ":"),
            intPart,
            string.concat(".", vm.toString(fracPart), " ", symbol)
        );
    }

    /**
     * 测试: 提现100U, 10%手续费, 验证swap兑换
     */
    function testWithdrawWithSwap() public {
        uint256 amount = 100 ether;
        uint256 feePercent = 10;
        uint256 nonce = withdraw.accountNonce(alice);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(
            alice,
            amount,
            USDT_ADDR,
            feePercent,
            nonce,
            deadline
        );

        address receiver = withdraw.feeReceiver();
        IERC20 target = IERC20(MC_TOKEN);

        uint256 aliceBefore = usdt.balanceOf(alice);
        uint256 receiverUsdtBefore = usdt.balanceOf(receiver);
        uint256 receiverTokenBefore = target.balanceOf(receiver);

        console.log(unicode"\n=== 提现100U, 手续费10% ===");

        vm.prank(alice, alice);
        withdraw.withdrawal(
            amount,
            USDT_ADDR,
            feePercent,
            nonce,
            deadline,
            sig
        );

        uint256 aliceReceived = usdt.balanceOf(alice) - aliceBefore;
        uint256 receiverUsdt = usdt.balanceOf(receiver) - receiverUsdtBefore;
        uint256 receiverToken = target.balanceOf(receiver) -
            receiverTokenBefore;

        _logAmount(unicode"Alice 收到", aliceReceived, 18, "USDT");
        _logAmount(unicode"手续费USDT", receiverUsdt, 18, "USDT");
        _logAmount(
            unicode"手续费Token",
            receiverToken,
            IERC20Metadata(MC_TOKEN).decimals(),
            "Token"
        );

        // Alice 应收到 90U
        assertEq(aliceReceived, 90 ether, unicode"Alice 应收到 90U");
        // 手续费接收 5U (10U的50%)
        assertEq(receiverUsdt, 5 ether, unicode"手续费USDT应为5U");
        // swap 应买到代币
        assertGt(receiverToken, 0, unicode"应swap到目标代币");
    }

    /**
     * 测试: 提现无手续费
     */
    function testWithdrawNoFee() public {
        uint256 amount = 50 ether;
        uint256 nonce = withdraw.accountNonce(alice);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(alice, amount, USDT_ADDR, 0, nonce, deadline);

        uint256 before = usdt.balanceOf(alice);

        vm.prank(alice, alice);
        withdraw.withdrawal(amount, USDT_ADDR, 0, nonce, deadline, sig);

        uint256 received = usdt.balanceOf(alice) - before;
        assertEq(received, 50 ether, unicode"应收到全部50U");
    }

    /**
     * 测试: 签名篡改应失败
     */
    function testRevertTamperedSignature() public {
        uint256 amount = 100 ether;
        uint256 nonce = withdraw.accountNonce(alice);
        uint256 deadline = block.timestamp + 1 hours;

        // 签名时 feePercent=10, 调用时传 0
        bytes memory sig = _sign(alice, amount, USDT_ADDR, 10, nonce, deadline);

        vm.prank(alice, alice);
        vm.expectRevert("invalid signature");
        withdraw.withdrawal(amount, USDT_ADDR, 0, nonce, deadline, sig);
    }

    /**
     * 测试: 重复nonce应失败
     */
    function testRevertDuplicateNonce() public {
        uint256 amount = 10 ether;
        uint256 nonce = withdraw.accountNonce(alice);
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _sign(alice, amount, USDT_ADDR, 0, nonce, deadline);

        vm.prank(alice, alice);
        withdraw.withdrawal(amount, USDT_ADDR, 0, nonce, deadline, sig);

        // 跳过1分钟冷却
        vm.warp(block.timestamp + 2 minutes);

        // 相同nonce再次提现应失败
        vm.prank(alice, alice);
        vm.expectRevert("nonce is already exists");
        withdraw.withdrawal(amount, USDT_ADDR, 0, nonce, deadline, sig);
    }

    /**
     * 测试: 暂停时应失败
     */
    function testRevertWhenPaused() public {
        vm.prank(ADMIN);
        withdraw.setPause(true);

        uint256 nonce = withdraw.accountNonce(alice);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(
            alice,
            10 ether,
            USDT_ADDR,
            0,
            nonce,
            deadline
        );

        vm.prank(alice, alice);
        vm.expectRevert("Withdrawal: is pause");
        withdraw.withdrawal(10 ether, USDT_ADDR, 0, nonce, deadline, sig);
    }
}
