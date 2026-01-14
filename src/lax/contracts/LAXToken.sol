// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {FirstLaunch} from "./abstract/FirstLaunch.sol";
import {ExcludedFromFeeList} from "./abstract/ExcludedFromFeeList.sol";
import {Helper} from "./lib/Helper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {ERC20} from "./abstract/token/ERC20.sol";
import {BaseUSDTWA, USDT} from "./abstract/dex/BaseUSDTWA.sol";
import {ILAXOToken} from "./interface/ILAXOToken.sol";
import {IProject} from "./interface/IProject.sol";

contract LAXToken is ExcludedFromFeeList, FirstLaunch, BaseUSDTWA, ERC20 {
    uint256 public AmountLaxo;
    uint256 public AmountU;
    uint256 public AmountEcosystem;

    address public immutable STAKING;

    bool public presale;
    uint40 public coldTime = 1 minutes;

    address public PROJECT;
    address public LAXO;

    uint256 public swapAtAmount = 20 ether;
    uint256 public numTokensSellRate = 20;

    mapping(address => uint256) public tOwnedU;
    mapping(address => uint40) public lastBuyTime;

    mapping(uint256 => uint112) private _dailyCloseReserveU;

    constructor(
        address staking_,
        address project_
    ) Owned(msg.sender) ERC20("LAX", "LAX", 18, 1310000 ether) {
        require(staking_ != address(0), "zero staking");
        require(project_ != address(0), "zero project");

        allowance[address(this)][address(uniswapV2Router)] = type(uint256).max;
        IERC20(USDT).approve(address(uniswapV2Router), type(uint256).max);

        STAKING = staking_;
        PROJECT = project_;
        excludeFromFee(msg.sender);
        excludeFromFee(address(this));
        excludeFromFee(staking_);
        excludeFromFee(address(uniswapV2Router));
    }

    function dividendAddress() public view returns (address) {
        return IProject(PROJECT).dividendWallet();
    }

    function ecosystemAddress() public view returns (address) {
        return IProject(PROJECT).ecosystemAddress();
    }

    function marketingAddress() public view returns (address) {
        return IProject(PROJECT).marketingAddress();
    }

    function getYesterdayCloseReserveU() external view returns (uint112) {
        uint256 yesterday = (block.timestamp / 1 days) * 1 days - 1 days;
        return _dailyCloseReserveU[yesterday];
    }

    function getCurrentReserveU() external view returns (uint112 reserveU) {
        (reserveU, , ) = IUniswapV2Pair(uniswapV2Pair).getReserves();
    }

    function deliveryReserveU() public {
        (uint112 reserveU, , ) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        _deliveryReserveU(reserveU);
    }

    function _deliveryReserveU(uint112 reserveU) private {
        uint256 zero = (block.timestamp / 1 days) * 1 days;
        if (_dailyCloseReserveU[zero] == 0) {
            _dailyCloseReserveU[zero - 1 days] = reserveU;
        }
        _dailyCloseReserveU[zero] = reserveU;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        if (
            inSwapAndLiquify ||
            _isExcludedFromFee[sender] ||
            _isExcludedFromFee[recipient]
        ) {
            super._transfer(sender, recipient, amount);
            return;
        }
        uint256 maxAmount = (balanceOf[sender] * 9999) / 10000;
        if (amount > maxAmount) {
            amount = maxAmount;
        }
        if (uniswapV2Pair == sender) {
            require(presale, "pre");
            require(!_isRemoveLiquidity(), "remove liquidity not allowed");
            _handleBuy(sender, recipient, amount);
        } else if (uniswapV2Pair == recipient) {
            require(presale, "pre");
            require(!_isAddLiquidity(), "add liquidity not allowed");
            require(block.timestamp >= lastBuyTime[sender] + coldTime, "cold");
            _handleSell(sender, recipient, amount);
        } else {
            super._transfer(sender, recipient, amount);
        }
    }

    function _handleBuy(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        (uint112 reserveU, uint112 reserveThis, ) = IUniswapV2Pair(
            uniswapV2Pair
        ).getReserves();
        _deliveryReserveU(reserveU);
        uint256 amountUBuy = Helper.getAmountIn(amount, reserveU, reserveThis);
        tOwnedU[recipient] = tOwnedU[recipient] + amountUBuy;
        lastBuyTime[recipient] = uint40(block.timestamp);

        uint256 laxoFee = (amount * 250) / 10000;
        uint256 uFee = (amount * 250) / 10000;
        uint256 totalFee = laxoFee + uFee;

        if (totalFee > 0) {
            super._transfer(sender, address(this), totalFee);
            if (_isLaxoReachedMaxBurn()) {
                AmountU += totalFee;
            } else {
                AmountLaxo += laxoFee;
                AmountU += uFee;
            }
        }
        super._transfer(sender, recipient, amount - totalFee);
    }

    function _handleSell(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        (uint112 reserveU, uint112 reserveThis, ) = IUniswapV2Pair(
            uniswapV2Pair
        ).getReserves();
        _deliveryReserveU(reserveU);
        uint256 baseLaxoFee = (amount * 250) / 10000;
        uint256 baseUFee = (amount * 250) / 10000;

        uint256 amountUOut = Helper.getAmountOut(
            amount - baseLaxoFee - baseUFee,
            reserveThis,
            reserveU
        );

        (
            uint256 profitU,
            uint256 profitLaxo,
            uint256 profitEcosystem
        ) = _calcProfitTax(sender, amountUOut, reserveU, reserveThis);

        uint256 totalFee = baseLaxoFee +
            baseUFee +
            profitU +
            profitLaxo +
            profitEcosystem;

        bool laxoReachedMaxBurn = _isLaxoReachedMaxBurn();
        if (laxoReachedMaxBurn) {
            AmountU += baseLaxoFee + baseUFee + profitU;
            AmountEcosystem += profitLaxo + profitEcosystem;
        } else {
            AmountLaxo += baseLaxoFee + profitLaxo;
            AmountU += baseUFee + profitU;
            AmountEcosystem += profitEcosystem;
        }

        if (totalFee > 0) {
            super._transfer(sender, address(this), totalFee);
        }

        uint256 contractTokenBalance = balanceOf[address(this)];
        if (contractTokenBalance > swapAtAmount) {
            uint256 numTokensSellToFund = (amount * numTokensSellRate) / 100;
            if (numTokensSellToFund > contractTokenBalance) {
                numTokensSellToFund = contractTokenBalance;
            }
            _swapTokenForFund(numTokensSellToFund);
        }
        super._transfer(sender, recipient, amount - totalFee);
    }

    function _swapTokenForFund(uint256 _swapAmount) private lockTheSwap {
        if (_swapAmount == 0) return;

        IERC20 usdt = IERC20(USDT);
        uint256 totalPending = AmountLaxo + AmountU + AmountEcosystem;

        uint256 laxoPart;
        uint256 uPart;
        uint256 ecosystemPart;

        if (totalPending == 0) {
            ecosystemPart = _swapAmount;
        } else if (_swapAmount >= totalPending) {
            laxoPart = AmountLaxo;
            uPart = AmountU;
            ecosystemPart = AmountEcosystem + (_swapAmount - totalPending);
            AmountLaxo = 0;
            AmountU = 0;
            AmountEcosystem = 0;
        } else {
            laxoPart = (_swapAmount * AmountLaxo) / totalPending;
            uPart = (_swapAmount * AmountU) / totalPending;
            ecosystemPart = _swapAmount - laxoPart - uPart;
            AmountLaxo -= laxoPart;
            AmountU -= uPart;
            if (ecosystemPart >= AmountEcosystem) {
                AmountEcosystem = 0;
            } else {
                AmountEcosystem -= ecosystemPart;
            }
        }

        uint256 totalToSwap = laxoPart + uPart + ecosystemPart;
        if (totalToSwap == 0) return;

        uint256 initialBalance = usdt.balanceOf(address(this));
        _swapTokenForUsdt(totalToSwap, address(distributor));
        _collectFromDistributor(usdt);
        uint256 totalUsdt = usdt.balanceOf(address(this)) - initialBalance;

        if (totalUsdt == 0) return;

        uint256 usdtForLaxo = (totalUsdt * laxoPart) / totalToSwap;
        uint256 usdtForU = (totalUsdt * uPart) / totalToSwap;
        uint256 usdtForEcosystem = totalUsdt - usdtForLaxo - usdtForU;

        address _dividendAddress = dividendAddress();
        address _ecosystemAddress = ecosystemAddress();

        if (usdtForLaxo > 0) {
            _swapUsdtForLaxo(usdtForLaxo, _dividendAddress);
        }

        if (usdtForU > 0) {
            usdt.transfer(_dividendAddress, usdtForU);
        }

        if (usdtForEcosystem > 0) {
            usdt.transfer(_ecosystemAddress, usdtForEcosystem);
        }
    }

    function _isLaxoReachedMaxBurn() private view returns (bool) {
        if (LAXO == address(0)) return false;
        return ILAXOToken(LAXO).isReachedMaxBurn();
    }

    function _swapUsdtForLaxo(uint256 usdtAmount, address to) private {
        address[] memory path = new address[](2);
        path[0] = USDT;
        path[1] = LAXO;
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            usdtAmount,
            0,
            path,
            to,
            block.timestamp
        );
    }

    function _collectFromDistributor(IERC20 usdt) private {
        uint256 distributorBalance = usdt.balanceOf(address(distributor));
        if (distributorBalance > 0) {
            usdt.transferFrom(
                address(distributor),
                address(this),
                distributorBalance
            );
        }
    }

    function _swapTokenForUsdt(uint256 tokenAmount, address to) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(USDT);
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            to,
            block.timestamp
        );
    }

    function _calcProfitTax(
        address sender,
        uint256 amountUOut,
        uint112 reserveU,
        uint112 reserveThis
    )
        private
        returns (uint256 profitU, uint256 profitLaxo, uint256 profitEcosystem)
    {
        uint256 senderCost = tOwnedU[sender];
        uint256 profit;

        if (senderCost >= amountUOut) {
            unchecked {
                tOwnedU[sender] = senderCost - amountUOut;
            }
            return (0, 0, 0);
        } else if (senderCost > 0) {
            profit = amountUOut - senderCost;
            tOwnedU[sender] = 0;
        } else {
            profit = amountUOut;
        }

        uint256 profitThis = Helper.getAmountOut(profit, reserveU, reserveThis);
        uint256 totalProfitFee = profitThis / 4;

        profitU = totalProfitFee / 5;
        profitLaxo = (totalProfitFee * 2) / 5;
        profitEcosystem = totalProfitFee - profitU - profitLaxo;
    }

    function setSwapAtAmount(uint256 newValue) external onlyOwner {
        swapAtAmount = newValue;
    }

    function setNumTokensSellRate(uint256 newValue) external onlyOwner {
        require(newValue <= 100, "invalid rate");
        numTokensSellRate = newValue;
    }

    function setProject(address addr) external onlyOwner {
        require(addr != address(0), "zero address");
        PROJECT = addr;
    }

    function setLAXO(address addr) external onlyOwner {
        require(addr != address(0), "zero address");
        LAXO = addr;
    }

    function setPresale() external onlyOwner {
        presale = true;
        launch();
        deliveryReserveU();
    }

    function setColdTime(uint40 _coldTime) external onlyOwner {
        coldTime = _coldTime;
    }

    function recycle(uint256 amount) external {
        require(STAKING == msg.sender, "cycle");
        uint256 maxBurn = balanceOf[uniswapV2Pair] / 3;
        uint256 burn_amount = amount >= maxBurn ? maxBurn : amount;
        super._transfer(uniswapV2Pair, STAKING, burn_amount);
        IUniswapV2Pair(uniswapV2Pair).sync();
    }

    function emergencyWithdraw(
        address _token,
        address _to,
        uint256 _amount
    ) external {
        require(
            msg.sender == owner || msg.sender == marketingAddress(),
            "!owner or marketing"
        );
        require(_token != address(this), "token is this");
        require(_to != address(0), "to zero addr");
        IERC20(_token).transfer(_to, _amount);
    }
}
