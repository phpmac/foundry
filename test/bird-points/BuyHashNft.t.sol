// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 运行命令:
// forge test --match-path test/bird-points/BuyHashNft.t.sol -vvv --offline

import {BuyHashNft} from "../../src/bird-points/BuyHashNft.sol";
import {HashNft} from "../../src/bird-points/HashNft.sol";
import {SimpleToken} from "../../src/simple/SimpleToken.sol";
import {Invite} from "../../src/bird-points/Invite.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

contract BuyHashNftTest is Test {
    BuyHashNft public buyHashNft;
    HashNft public nft;
    SimpleToken public usdt;
    Invite public invite;

    address public owner;
    address public alice;
    address public bob;
    address public treasuryWallet;

    uint256 public constant TEST_CHAIN_ID = 97;
    uint256 public constant PRICE = 500 ether;

    function setUp() public {
        vm.chainId(TEST_CHAIN_ID);

        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        treasuryWallet = makeAddr("treasuryWallet");

        // 部署 USDT
        SimpleToken usdtImpl = new SimpleToken();
        ERC1967Proxy usdtProxy = new ERC1967Proxy(
            address(usdtImpl),
            abi.encodeWithSelector(SimpleToken.initialize.selector, "USDT", "USDT", 1000000 ether)
        );
        usdt = SimpleToken(address(usdtProxy));

        // 部署 HashNft
        HashNft nftImpl = new HashNft();
        ERC1967Proxy nftProxy = new ERC1967Proxy(
            address(nftImpl),
            abi.encodeWithSelector(HashNft.initialize.selector, "HashNft", "HNFT")
        );
        nft = HashNft(address(nftProxy));

        // 部署 Invite
        Invite inviteImpl = new Invite();
        ERC1967Proxy inviteProxy = new ERC1967Proxy(
            address(inviteImpl),
            abi.encodeWithSelector(Invite.initialize.selector, owner)
        );
        invite = Invite(address(inviteProxy));

        // 部署 BuyHashNft
        BuyHashNft buyHashNftImpl = new BuyHashNft();
        ERC1967Proxy buyHashNftProxy = new ERC1967Proxy(
            address(buyHashNftImpl),
            abi.encodeWithSelector(
                BuyHashNft.initialize.selector,
                address(usdt),
                address(nft),
                address(invite),
                treasuryWallet
            )
        );
        buyHashNft = BuyHashNft(address(buyHashNftProxy));

        // 授予 MINTER_ROLE
        nft.grantRole(nft.MINTER_ROLE(), address(buyHashNft));
    }

    // 部署验证
    function test_Deployment() public view {
        assertEq(address(buyHashNft.usdt()), address(usdt));
        assertEq(address(buyHashNft.nft()), address(nft));
        assertEq(buyHashNft.treasuryWallet(), treasuryWallet);
        assertEq(buyHashNft.PRICE(), PRICE);
        assertEq(buyHashNft.totalSold(), 0);
        assertFalse(buyHashNft.isPaused());

        console.log(unicode"部署验证通过");
    }

    // 购买成功 - 核心验证: NFT数量 / 总销售量 / 收款地址余额
    function test_BuySuccess() public {
        usdt.transfer(alice, PRICE);
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);

        vm.startPrank(alice, alice);
        usdt.approve(address(buyHashNft), PRICE);
        buyHashNft.buy(1);
        vm.stopPrank();

        // 核心验证
        assertEq(nft.balanceOf(alice), 1, "NFT balance");
        assertEq(buyHashNft.totalSold(), 1, "Total sold");
        assertEq(usdt.balanceOf(treasuryWallet), PRICE, "Treasury balance");

        console.log(unicode"购买成功测试通过");
    }

    // 未绑定邀请人购买失败
    function test_BuyWithoutInviter() public {
        usdt.transfer(bob, PRICE);

        vm.startPrank(bob, bob);
        usdt.approve(address(buyHashNft), PRICE);
        vm.expectRevert("No inviter bound");
        buyHashNft.buy(1);
        vm.stopPrank();

        console.log(unicode"未绑定邀请人测试通过");
    }

    // 暂停功能
    function test_Pause() public {
        usdt.transfer(alice, PRICE);
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);
        vm.prank(alice, alice);
        usdt.approve(address(buyHashNft), PRICE);

        // 暂停后无法购买
        buyHashNft.pause();
        vm.prank(alice, alice);
        vm.expectRevert("Paused");
        buyHashNft.buy(1);

        // 恢复后可购买
        buyHashNft.unpause();
        vm.prank(alice, alice);
        buyHashNft.buy(1);

        assertEq(nft.balanceOf(alice), 1);

        console.log(unicode"暂停功能测试通过");
    }

    // 边界测试: 购买数量为 0 失败
    function test_BuyWithZeroAmount() public {
        usdt.transfer(alice, PRICE);
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);

        vm.startPrank(alice, alice);
        usdt.approve(address(buyHashNft), PRICE);
        vm.expectRevert("Amount must > 0");
        buyHashNft.buy(0);
        vm.stopPrank();

        console.log(unicode"购买数量为 0 测试通过");
    }

    // 边界测试: USDT 余额不足失败
    function test_BuyWithInsufficientBalance() public {
        // 只给一半的 USDT
        usdt.transfer(alice, PRICE / 2);
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);

        vm.startPrank(alice, alice);
        usdt.approve(address(buyHashNft), PRICE);
        vm.expectRevert(); // USDT transferFrom 会失败
        buyHashNft.buy(1);
        vm.stopPrank();

        console.log(unicode"USDT 余额不足测试通过");
    }

    // 边界测试: USDT 授权不足失败
    function test_BuyWithInsufficientAllowance() public {
        usdt.transfer(alice, PRICE);
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);

        // 只授权一半的额度
        vm.startPrank(alice, alice);
        usdt.approve(address(buyHashNft), PRICE / 2);
        vm.expectRevert(); // USDT transferFrom 会抛出 ERC20InsufficientAllowance
        buyHashNft.buy(1);
        vm.stopPrank();

        console.log(unicode"USDT 授权不足测试通过");
    }

    // 边界测试: 多次购买 (累加计数)
    function test_MultipleBuys() public {
        uint256 totalAmount = PRICE * 3;
        usdt.transfer(alice, totalAmount);
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);

        vm.startPrank(alice, alice);
        usdt.approve(address(buyHashNft), totalAmount);

        // 分 3 次购买
        buyHashNft.buy(1);
        buyHashNft.buy(1);
        buyHashNft.buy(1);
        vm.stopPrank();

        // 验证累加
        assertEq(nft.balanceOf(alice), 3, "NFT balance should be 3");
        assertEq(buyHashNft.totalSold(), 3, "Total sold should be 3");
        assertEq(usdt.balanceOf(treasuryWallet), totalAmount, "Treasury balance");

        console.log(unicode"多次购买测试通过");
    }

    // 边界测试: NFT 转赠功能
    function test_NftTransfer() public {
        usdt.transfer(alice, PRICE);
        vm.prank(owner);
        invite.bindParentFrom(alice, owner);

        // alice 购买
        vm.startPrank(alice, alice);
        usdt.approve(address(buyHashNft), PRICE);
        buyHashNft.buy(1);
        vm.stopPrank();

        // alice 转赠给 bob
        uint256 tokenId = nft.tokenOfOwnerByIndex(alice, 0);
        vm.prank(alice, alice);
        nft.transferFrom(alice, bob, tokenId);

        // 验证所有权转移
        assertEq(nft.balanceOf(alice), 0, "Alice should have 0 NFT");
        assertEq(nft.balanceOf(bob), 1, "Bob should have 1 NFT");
        assertEq(nft.ownerOf(tokenId), bob, "Token owner should be bob");

        console.log(unicode"NFT 转赠测试通过");
    }
}