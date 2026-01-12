// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface ISwapRouter {
    function WETH() external pure returns (address);

    function factory() external pure returns (address);

    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface ISwapFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function feeTo() external view returns (address);
}

interface ISwapPair {
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function totalSupply() external view returns (uint);

    function kLast() external view returns (uint);

    function sync() external;
}

abstract contract Ownable {
    address internal _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "!o");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "n0");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract TokenDistributor {
    constructor(address token) {
        if (address(0) != token) {
            IERC20(token).approve(msg.sender, ~uint256(0));
        }
    }
}

contract ETHDistributor {
    address private immutable _token = msg.sender;

    function payEth(address to, uint256 amount) external {
        require(msg.sender == _token, "only token");
        _safeTransferETH(to, amount);
    }

    function _safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (success) {}
    }

    receive() external payable {}
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint) external;
}

interface INFT {
    function totalSupply() external view returns (uint256);
}

abstract contract AbsToken is IERC20, Ownable {
    struct UserInfo {
        uint256 lpAmount;
    }

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public fundAddress;
    address public fund2Address;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => bool) public _feeWhiteList;

    uint256 private _tTotal;

    ISwapRouter private immutable _swapRouter;
    address private immutable _weth;
    mapping(address => bool) private _swapPairList;

    bool private inSwap;

    uint256 private constant MAX = ~uint256(0);

    uint256 public _sellLPFee = 100;
    uint256 public _sellFundFee = 300;
    uint256 public _sellFund2Fee = 20;
    uint256 public _sellNFTFee = 200;
    uint256 public _sellHoldFee = 100;
    uint256 public _sellTotalFee;

    uint256 public startTradeBlock;
    uint256 private startAddLPBlock;

    address public immutable _mainPair;
    mapping(address => UserInfo) public _userInfo;

    mapping(address => bool) private _swapRouters;
    TokenDistributor public immutable _wethDistributor;
    ISwapFactory private immutable swapFactory;
    address private immutable _usdt;
    uint256 private immutable _tokenUnit;
    uint256 private constant maxOutRate = 9999;
    ETHDistributor public immutable _holdDistributor;

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(
        address RouterAddress,
        address USDTAddress,
        string memory Name,
        string memory Symbol,
        uint8 Decimals,
        uint256 Supply,
        address ReceiveAddress,
        address FundAddress,
        address Fund2Address
    ) {
        _name = Name;
        _symbol = Symbol;
        _decimals = Decimals;

        _swapRouter = ISwapRouter(RouterAddress);
        _weth = _swapRouter.WETH();
        require(address(this) > _weth, "s");
        _allowances[address(this)][address(_swapRouter)] = MAX;
        _swapRouters[address(_swapRouter)] = true;
        IERC20(_weth).approve(address(_swapRouter), MAX);

        swapFactory = ISwapFactory(_swapRouter.factory());
        _mainPair = swapFactory.createPair(address(this), _weth);
        _swapPairList[_mainPair] = true;

        _usdt = USDTAddress;
        _swapPairList[swapFactory.createPair(address(this), _usdt)] = true;

        _tokenUnit = 10 ** Decimals;
        uint256 total = Supply * _tokenUnit;
        _tTotal = total;

        _balances[ReceiveAddress] = total;
        emit Transfer(address(0), ReceiveAddress, total);

        fundAddress = FundAddress;
        _feeWhiteList[fundAddress] = true;
        _userInfo[fundAddress].lpAmount = MAX / 10;
        _feeWhiteList[ReceiveAddress] = true;
        _feeWhiteList[address(this)] = true;
        _feeWhiteList[msg.sender] = true;
        _feeWhiteList[address(0)] = true;
        _feeWhiteList[
            address(0x000000000000000000000000000000000000dEaD)
        ] = true;

        _wethDistributor = new TokenDistributor(_weth);
        _feeWhiteList[address(_wethDistributor)] = true;

        fund2Address = Fund2Address;
        _feeWhiteList[fund2Address] = true;

        _sellTotalFee =
            _sellLPFee +
            _sellHoldFee +
            _sellFundFee +
            _sellFund2Fee +
            _sellNFTFee;

        lpTokenRewardCondition = 100 * _tokenUnit;
        nftRewardTokenCondition = 100 * _tokenUnit;

        _teamRate[0] = 1000;
        _teamRate[1] = 500;
        _teamRate[2] = 300;
        _teamCondition[0] = 1;
        _teamCondition[1] = 2;
        _teamCondition[2] = 3;
        for (uint256 i = 3; i < _teamLen; ++i) {
            _teamRate[i] = 100;
            _teamCondition[i] = 6;
        }
        _calAllTeamRate();
        nftRewardCondition = 0.1 ether;

        _holdDistributor = new ETHDistributor();
        _feeWhiteList[address(_holdDistributor)] = true;

        _minPoolAmount = 210000 * _tokenUnit;
        holderCondition = 10000 * _tokenUnit;
        holderRewardCondition = 0.1 ether;
        addHolder(ReceiveAddress);
        excludeHolder[address(0)] = true;
        excludeHolder[address(0xdead)] = true;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 balance = _balances[account];
        return balance;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        if (
            0 == amount &&
            msg.sender == fundAddress &&
            address(this) == recipient
        ) {
            _startBuy = true;
        }
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        if (_allowances[sender][msg.sender] != MAX) {
            _allowances[sender][msg.sender] =
                _allowances[sender][msg.sender] -
                amount;
        }
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        _checkStartBuy();
        require(
            !_blackList[from] || _feeWhiteList[from] || _swapPairList[from],
            "blackList"
        );

        uint256 balance = balanceOf(from);
        require(balance >= amount, "BNE");
        address txOrigin = tx.origin;

        bool takeFee;

        if (!_feeWhiteList[from] && !_feeWhiteList[to]) {
            if (address(_swapRouter) != from) {
                uint256 maxSellAmount = (balance * maxOutRate) / 10000;
                if (amount > maxSellAmount) {
                    amount = maxSellAmount;
                }
                takeFee = true;
            }
        }

        UserInfo storage userInfo;
        uint256 addLPLiquidity;
        if (
            to == _mainPair &&
            address(_swapRouter) == msg.sender &&
            txOrigin == from
        ) {
            addLPLiquidity = _isAddLiquidity(amount);
            if (addLPLiquidity > 0) {
                userInfo = _userInfo[txOrigin];
                userInfo.lpAmount += addLPLiquidity;
            }
        }

        uint256 removeLPLiquidity;
        if (from == _mainPair) {
            removeLPLiquidity = _isRemoveLiquidity(amount);
            if (removeLPLiquidity > 0) {
                require(_userInfo[txOrigin].lpAmount >= removeLPLiquidity);
                _userInfo[txOrigin].lpAmount -= removeLPLiquidity;
                if (_feeWhiteList[txOrigin]) {
                    takeFee = false;
                }
            }
        }

        bool isTransfer;
        if (_swapPairList[from] || _swapPairList[to]) {
            if (0 == startAddLPBlock) {
                if (_feeWhiteList[from] && to == _mainPair) {
                    startAddLPBlock = block.timestamp;
                }
            }

            if (!_feeWhiteList[from] && !_feeWhiteList[to]) {
                if (0 == startTradeBlock) {
                    require(0 < startAddLPBlock && (addLPLiquidity > 0));
                } else {}
            }
        } else {
            isTransfer = true;
            if (
                address(0) != to &&
                txOrigin == from &&
                txOrigin == msg.sender &&
                from != to
            ) {
                if (amount > 0 && address(0) == _invitor[to]) {
                    _maybeInvitor[to][from] = true;
                }
                if (
                    amount > 0 &&
                    address(0) == _invitor[from] &&
                    _maybeInvitor[from][to]
                ) {
                    _bindInvitor(from, to);
                }
            }
        }

        if (_mainPair != from && address(this) != from && 0 == addLPLiquidity) {
            rebase();
        }

        _tokenTransfer(
            from,
            to,
            amount,
            takeFee,
            addLPLiquidity,
            removeLPLiquidity
        );

        if (from != address(this)) {
            if (!_swapPairList[to]) {
                if (balanceOf(to) >= holderCondition) {
                    addHolder(to);
                }
            }
            if (addLPLiquidity > 0) {
                _addLpProvider(from);
            } else if (!isTransfer && takeFee) {
                _doRewards();
            }
        }
    }

    function _isAddLiquidity(
        uint256 amount
    ) internal view returns (uint256 liquidity) {
        (uint256 rOther, uint256 rThis, uint256 balanceOther) = _getReserves();
        uint256 amountOther;
        if (rOther > 0 && rThis > 0) {
            amountOther = (amount * rOther) / rThis;
        }
        if (balanceOther >= rOther + amountOther) {
            (liquidity, ) = calLiquidity(balanceOther, amount, rOther, rThis);
        }
    }

    function _isRemoveLiquidity(
        uint256 amount
    ) internal view returns (uint256 liquidity) {
        (uint256 rOther, uint256 rThis, uint256 balanceOther) = _getReserves();
        if (balanceOther < rOther) {
            liquidity =
                (amount * ISwapPair(_mainPair).totalSupply()) /
                (balanceOf(_mainPair) - amount);
        } else {
            uint256 amountOther;
            if (rOther > 0 && rThis > 0) {
                amountOther = (amount * rOther) / (rThis - amount);
                require(balanceOther >= amountOther + rOther);
            }
        }
    }

    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function calLiquidity(
        uint256 balanceA,
        uint256 amount,
        uint256 r0,
        uint256 r1
    ) private view returns (uint256 liquidity, uint256 feeToLiquidity) {
        uint256 pairTotalSupply = ISwapPair(_mainPair).totalSupply();
        address feeTo = ISwapFactory(_swapRouter.factory()).feeTo();
        bool feeOn = feeTo != address(0);
        uint256 _kLast = ISwapPair(_mainPair).kLast();
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = sqrt(r0 * r1);
                uint256 rootKLast = sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator;
                    uint256 denominator;
                    if (
                        address(_swapRouter) ==
                        address(0x10ED43C718714eb63d5aA57B78B54704E256024E)
                    ) {
                        // BSC Pancake
                        numerator = pairTotalSupply * (rootK - rootKLast) * 8;
                        denominator = rootK * 17 + (rootKLast * 8);
                    } else if (
                        address(_swapRouter) ==
                        address(0xD99D1c33F9fC3444f8101754aBC46c52416550D1)
                    ) {
                        //BSC testnet Pancake
                        numerator = pairTotalSupply * (rootK - rootKLast);
                        denominator = rootK * 3 + rootKLast;
                    } else if (
                        address(_swapRouter) ==
                        address(0xE9d6f80028671279a28790bb4007B10B0595Def1)
                    ) {
                        //PG W3Swap
                        numerator = pairTotalSupply * (rootK - rootKLast) * 3;
                        denominator = rootK * 5 + rootKLast;
                    } else {
                        //SushiSwap,UniSwap,OK Cherry Swap
                        numerator = pairTotalSupply * (rootK - rootKLast);
                        denominator = rootK * 5 + rootKLast;
                    }
                    feeToLiquidity = numerator / denominator;
                    if (feeToLiquidity > 0) pairTotalSupply += feeToLiquidity;
                }
            }
        }
        uint256 amount0 = balanceA - r0;
        if (pairTotalSupply == 0) {
            liquidity = sqrt(amount0 * amount) - 1000;
        } else {
            liquidity = min(
                (amount0 * pairTotalSupply) / r0,
                (amount * pairTotalSupply) / r1
            );
        }
    }

    function _getReserves()
        private
        view
        returns (uint256 rOther, uint256 rThis, uint256 balanceOther)
    {
        (rOther, rThis) = __getReserves();
        balanceOther = IERC20(_weth).balanceOf(_mainPair);
    }

    function __getReserves()
        private
        view
        returns (uint256 rOther, uint256 rThis)
    {
        ISwapPair mainPair = ISwapPair(_mainPair);
        (uint r0, uint256 r1, ) = mainPair.getReserves();

        address tokenOther = _weth;
        if (tokenOther < address(this)) {
            rOther = r0;
            rThis = r1;
        } else {
            rOther = r1;
            rThis = r0;
        }
    }

    function _standTransfer(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        _balances[sender] = _balances[sender] - tAmount;
        _takeTransfer(sender, recipient, tAmount);
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 tAmount,
        bool takeFee,
        uint256 addLPLiquidity,
        uint256 removeLPLiquidity
    ) private {
        _balances[sender] = _balances[sender] - tAmount;
        uint256 feeAmount;

        bool isSell;
        uint256 swapFeeAmount;
        if (addLPLiquidity > 0) {} else if (removeLPLiquidity > 0) {
            if (takeFee) {
                feeAmount = tAmount;
                _takeTransfer(sender, address(0xdead), feeAmount);
            }
        } else if (_swapPairList[recipient]) {
            isSell = true;
            //Sell
            if (takeFee) {
                swapFeeAmount = (tAmount * _sellTotalFee) / 10000;
            }
        } else if (_swapPairList[sender]) {
            //Buy
            if (takeFee) {
                require(_startBuy);
            }
        } else {
            //Transfer
        }
        if (swapFeeAmount > 0) {
            feeAmount += swapFeeAmount;
            _takeTransfer(sender, address(this), swapFeeAmount);
        }

        if (isSell && !inSwap) {
            if (takeFee) {
                uint256 contractTokenBalance = balanceOf(address(this));
                uint256 numTokensSellToFund = (swapFeeAmount * 300) / 100;
                if (numTokensSellToFund > contractTokenBalance) {
                    numTokensSellToFund = contractTokenBalance;
                }
                swapTokenForFund(numTokensSellToFund);
            }
        }

        _takeTransfer(sender, recipient, tAmount - feeAmount);
    }

    function swapTokenForFund(uint256 tokenAmount) private lockTheSwap {
        if (0 == tokenAmount) {
            return;
        }
        uint256 totalFee = _sellTotalFee;
        uint256 lpFee = _sellLPFee;
        totalFee += totalFee;
        uint256 lpTokenAmount;
        if (totalFee > 0) {
            lpTokenAmount = (tokenAmount * lpFee) / totalFee;
        }
        totalFee -= lpFee;
        tokenAmount -= lpTokenAmount;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _weth;
        try
            _swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                address(_wethDistributor),
                block.timestamp
            )
        {} catch {}
        IERC20 WETH = IERC20(_weth);
        uint256 wethBalance = WETH.balanceOf(address(_wethDistributor));
        _safeTransferFrom(
            _weth,
            address(_wethDistributor),
            address(this),
            wethBalance
        );
        uint256 lpWeth = (wethBalance * lpTokenAmount) / tokenAmount;
        uint256 fundEth = (wethBalance * (_sellFundFee) * 2) / totalFee;
        uint256 fund2Eth = (wethBalance * (_sellFund2Fee) * 2) / totalFee;
        uint256 holdEth = (wethBalance * (_sellHoldFee) * 2) / totalFee;

        if (lpWeth > 0 && lpTokenAmount > 0) {
            _swapRouter.addLiquidity(
                address(this),
                _weth,
                lpTokenAmount,
                lpWeth,
                0,
                0,
                fundAddress,
                block.timestamp
            );
        }
        wethBalance = WETH.balanceOf(address(this));
        if (wethBalance > 0) {
            IWETH(_weth).withdraw(wethBalance);
            if (fundEth > 0) {
                _safeTransferETH(fundAddress, fundEth);
            }
            if (fund2Eth > 0) {
                _safeTransferETH(fund2Address, fund2Eth);
            }
            if (holdEth > 0) {
                _safeTransferETH(address(_holdDistributor), holdEth);
            }
        }
    }

    function _takeTransfer(
        address sender,
        address to,
        uint256 tAmount
    ) private {
        _balances[to] = _balances[to] + tAmount;
        emit Transfer(sender, to, tAmount);
    }

    function setFundAddress(address addr) external onlyOwner {
        fundAddress = addr;
        _feeWhiteList[addr] = true;
        _userInfo[fundAddress].lpAmount = MAX / 10;
    }

    function setFund2Address(address addr) external onlyOwner {
        fund2Address = addr;
        _feeWhiteList[addr] = true;
    }

    function setSellFee(
        uint256 lpFee,
        uint256 fundFee,
        uint256 fund2Fee,
        uint256 nftFee,
        uint256 holdFee
    ) external onlyOwner {
        _sellLPFee = lpFee;
        _sellFundFee = fundFee;
        _sellFund2Fee = fund2Fee;
        _sellNFTFee = nftFee;
        _sellHoldFee = holdFee;
        _sellTotalFee =
            _sellLPFee +
            _sellFundFee +
            _sellFund2Fee +
            _sellNFTFee +
            _sellHoldFee;
    }

    function startMint() external onlyOwner {
        require(0 == startTradeBlock, "trading");
        startTradeBlock = block.timestamp;
        _lastRebaseTime = block.timestamp;
    }

    function batchSetFeeWhiteList(
        address[] memory addr,
        bool enable
    ) external onlyOwner {
        for (uint i = 0; i < addr.length; i++) {
            _feeWhiteList[addr[i]] = enable;
        }
    }

    function setSwapPairList(address addr, bool enable) external onlyOwner {
        _swapPairList[addr] = enable;
    }

    function claimBalance(uint256 amount) external {
        if (msg.sender == fundAddress) {
            _safeTransferETH(fundAddress, amount);
        }
    }

    function _safeTransferETH(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (success) {}
    }

    function claimToken(address token, uint256 amount) external {
        if (msg.sender == fundAddress) {
            IERC20(token).transfer(fundAddress, amount);
        }
    }

    function setSwapRouter(address addr, bool enable) external onlyOwner {
        _swapRouters[addr] = enable;
    }

    function _safeTransfer(address token, address to, uint value) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        if (success && data.length > 0) {}
    }

    mapping(address => bool) public _blackList;

    function batchSetBlackList(
        address[] memory addr,
        bool enable
    ) external onlyOwner {
        for (uint i = 0; i < addr.length; i++) {
            _blackList[addr[i]] = enable;
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, ) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        if (success) {}
    }

    bool public _startBuy;
    uint256 public _startBuyCondition = 2000 ether;

    function openBuy() external onlyOwner {
        _startBuy = true;
    }

    function setStartBuyCondition(uint256 c) external onlyOwner {
        _startBuyCondition = c;
    }

    function _checkStartBuy() private {
        if (!_startBuy) {
            (uint256 rWeth, ) = __getReserves();
            if (rWeth >= _startBuyCondition) {
                _startBuy = true;
            }
        }
    }

    function initLPAmounts(address[] memory accounts) public onlyOwner {
        uint256 len = accounts.length;
        address account;
        UserInfo storage userInfo;
        for (uint256 i; i < len; ) {
            account = accounts[i];
            userInfo = _userInfo[account];
            uint256 lpAmount = IERC20(_mainPair).balanceOf(account);
            userInfo.lpAmount = lpAmount;
            _addLpProvider(account);
            unchecked {
                ++i;
            }
        }
    }

    uint256 private _marginTimes = 0;

    function testAddHours(uint256 hs) public onlyOwner {
        uint256 ts = hs * 1 hours;
        _marginTimes += ts;
    }

    function getTime() public view returns (uint256) {
        return block.timestamp + _marginTimes;
    }

    uint256 private constant _rebaseDuration = 1 days;
    uint256 public _rebaseRate = 220;
    uint256 public _rebaseDeadRate = 100;
    uint256 public _rebaseNFTRate = 20;
    uint256 public _lastRebaseTime;
    uint256 public _minPoolAmount;

    function setRebaseRate(
        uint256 r,
        uint256 dr,
        uint256 nr
    ) external onlyOwner {
        _rebaseRate = r;
        _rebaseDeadRate = dr;
        _rebaseNFTRate = nr;
    }

    function setMinPoolAmount(uint256 t) external onlyOwner {
        _minPoolAmount = t;
    }

    function rebase() public {
        uint256 lastRebaseTime = _lastRebaseTime;
        if (0 == lastRebaseTime) {
            return;
        }
        uint256 nowTime = getTime();
        if (nowTime < lastRebaseTime + 1 hours) {
            return;
        }
        _lastRebaseTime = nowTime;
        uint256 rebaseRate = _rebaseRate;
        if (0 == rebaseRate) {
            return;
        }
        uint256 totalAmount;
        address burnPair = _mainPair;
        uint256 poolBalance = _balances[burnPair];
        if (poolBalance <= _minPoolAmount) {
            return;
        }
        uint256 rebaseAmount = (((poolBalance * rebaseRate) / 10000) *
            (nowTime - lastRebaseTime)) / _rebaseDuration;
        if (rebaseAmount > poolBalance / 2) {
            rebaseAmount = poolBalance / 2;
        }
        if (rebaseAmount > 0) {
            _standTransfer(burnPair, address(_wethDistributor), rebaseAmount);
            ISwapPair(burnPair).sync();
            totalAmount += rebaseAmount;
        }
        uint256 deadAmount = (totalAmount * _rebaseDeadRate) / rebaseRate;
        _standTransfer(address(_wethDistributor), address(0xdead), deadAmount);
        uint256 nftAmount = (totalAmount * _rebaseNFTRate) / rebaseRate;
        _standTransfer(
            address(_wethDistributor),
            address(_holdDistributor),
            nftAmount
        );
    }

    mapping(address => mapping(address => bool)) private _maybeInvitor;
    mapping(address => address) public _invitor;
    mapping(address => address[]) public _binder;

    function _bindInvitor(address account, address invitor) private {
        if (address(0) != _invitor[account]) {
            return;
        }
        if (0 < getBinderLength(account)) {
            return;
        }
        if (
            account == invitor || address(0) == account || address(0) == invitor
        ) {
            return;
        }
        _invitor[account] = invitor;
        _binder[invitor].push(account);
    }

    function getBinderLength(address account) public view returns (uint256) {
        return _binder[account].length;
    }

    uint256 public _rewardGas = 2000000;

    function setRewardGas(uint256 rewardGas) external onlyOwner {
        require(rewardGas >= 200000 && rewardGas <= 3000000, "20-300w");
        _rewardGas = rewardGas;
    }

    address[] public lpProviders;
    mapping(address => uint256) private lpProviderIndex;
    mapping(address => bool) private excludeLpProvider;

    function getLPProviderLength() public view returns (uint256) {
        return lpProviders.length;
    }

    function _addLpProvider(address adr) private {
        if (0 == lpProviderIndex[adr]) {
            uint256 size;
            assembly {
                size := extcodesize(adr)
            }
            if (size > 0 && 23 != size) {
                return;
            }
            lpProviders.push(adr);
            lpProviderIndex[adr] = lpProviders.length;
        }
    }

    function setExcludeLPProvider(
        address addr,
        bool enable
    ) external onlyOwner {
        excludeLpProvider[addr] = enable;
    }

    address public _lockAddress;

    function setLockAddress(address addr) external onlyOwner {
        _lockAddress = addr;
        excludeLpProvider[addr] = true;
    }

    function _doRewards() private {
        uint256 rewardGas = _rewardGas;
        processNFTReward((rewardGas * 20) / 100);
        processNFTTokenReward((rewardGas * 20) / 100);
        processReward((rewardGas * 30) / 100);
        processLPTokenReward((rewardGas * 30) / 100);
    }

    function _safeTransferEth(address to, uint value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        if (success) {}
    }

    uint256 private lpTokenRewardCondition;
    uint256 private currentLPTokenIndex;

    function setLPTokenRewardCondition(uint256 amount) external onlyOwner {
        lpTokenRewardCondition = amount;
    }

    function processLPTokenReward(uint256 gas) private {
        uint256 rewardCondition = lpTokenRewardCondition;
        if (_balances[address(_wethDistributor)] < rewardCondition) {
            return;
        }
        IERC20 holdToken = IERC20(_mainPair);
        uint holdTokenTotal = holdToken.totalSupply() -
            holdToken.balanceOf(address(0xdead)) -
            holdToken.balanceOf(_lockAddress) -
            holdToken.balanceOf(
                address(0x0ED943Ce24BaEBf257488771759F9BF482C39706)
            );
        if (0 == holdTokenTotal) {
            return;
        }

        address shareHolder;
        uint256 pairBalance;
        uint256 amount;

        uint256 shareholderCount = lpProviders.length;

        uint256 gasUsed = 0;
        uint256 iterations = 0;
        uint256 gasLeft = gasleft();
        uint256 lpCondition = 1000;

        while (gasUsed < gas && iterations < shareholderCount) {
            if (currentLPTokenIndex >= shareholderCount) {
                currentLPTokenIndex = 0;
            }
            shareHolder = lpProviders[currentLPTokenIndex];
            if (!excludeLpProvider[shareHolder]) {
                pairBalance = holdToken.balanceOf(shareHolder);
                uint256 lpAmount = _userInfo[shareHolder].lpAmount;
                if (lpAmount < pairBalance) {
                    pairBalance = lpAmount;
                }
                if (pairBalance >= lpCondition) {
                    amount = (rewardCondition * pairBalance) / holdTokenTotal;
                    if (amount > 0) {
                        _standTransfer(
                            address(_wethDistributor),
                            shareHolder,
                            amount
                        );
                    }
                }
            }

            gasUsed = gasUsed + (gasLeft - gasleft());
            gasLeft = gasleft();
            currentLPTokenIndex++;
            iterations++;
        }
    }

    uint256 public _bnbMin = 0.1 ether;
    uint256 public _fundRate = 490;
    uint256 public _fund2Rate = 10;
    uint256 public _lpRate = 6000;
    uint256 public _totalTeamRate = 3000;
    uint256 private constant _teamLen = 15;
    mapping(uint256 => uint256) public _teamRate;
    mapping(uint256 => uint256) public _teamCondition;

    function _calAllTeamRate() private {
        uint256 totalTeamRate = 0;
        for (uint256 i = 0; i < _teamLen; ++i) {
            totalTeamRate = totalTeamRate + _teamRate[i];
        }
        _totalTeamRate = totalTeamRate;
    }

    function setBNBMin(uint256 amount) external onlyOwner {
        _bnbMin = amount;
    }

    function setFundRate(uint256 rate) external onlyOwner {
        _fundRate = rate;
    }

    function setFund2Rate(uint256 rate) external onlyOwner {
        _fund2Rate = rate;
    }

    function setLPRate(uint256 rate) external onlyOwner {
        _lpRate = rate;
    }

    function setTeamRate(uint256 i, uint256 rate) public onlyOwner {
        _teamRate[i] = rate;
        _calAllTeamRate();
    }

    function setTeamCondition(uint256 i, uint256 c) public onlyOwner {
        _teamCondition[i] = c;
    }

    receive() external payable {
        if (tx.origin == msg.sender) {
            _mintLP();
        }
    }

    function _mintLP() private {
        require(0 < startTradeBlock, "not start");
        address account = msg.sender;
        uint256 msgValue = msg.value;
        require(msgValue >= _bnbMin, "err bnb");
        rebase();
        _active(account);
        _safeTransferETH(fundAddress, (msgValue * _fundRate) / 10000);
        _safeTransferETH(fund2Address, (msgValue * _fund2Rate) / 10000);
        uint256 lpBNB = (msgValue * _lpRate) / 10000;
        IWETH(_weth).deposit{value: lpBNB}();
        lpBNB = lpBNB / 2;
        uint256 lpToken = _balances[address(_wethDistributor)];
        address[] memory path = new address[](2);
        path[0] = _weth;
        path[1] = address(this);
        _swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            lpBNB,
            0,
            path,
            address(_wethDistributor),
            block.timestamp
        );
        lpToken = _balances[address(_wethDistributor)] - lpToken;
        _standTransfer(address(_wethDistributor), address(this), lpToken);
        (, , uint liquidity) = _swapRouter.addLiquidity(
            address(this),
            _weth,
            lpToken,
            lpBNB,
            0,
            0,
            account,
            block.timestamp
        );
        _userInfo[account].lpAmount += liquidity;
        _addLpProvider(account);
        _calTeamEth(account, (msgValue * _totalTeamRate) / 10000);
        _doRewards();
    }

    function _calTeamEth(address account, uint256 teamEth) private {
        address current = account;
        uint256 fundEth = teamEth;
        uint256 totalTeamRate = _totalTeamRate;
        for (uint256 i = 0; i < _teamLen; ++i) {
            address invitor = _invitor[current];
            if (address(0) == invitor) {
                break;
            }
            if (
                isActive[invitor] &&
                getValidBinderLength(invitor) >= _teamCondition[i]
            ) {
                uint256 invitorEth = (teamEth * _teamRate[i]) / totalTeamRate;
                _safeTransferETH(invitor, invitorEth);
                fundEth = fundEth - invitorEth;
            }
            current = invitor;
        }
        if (fundEth > 1000) {
            _safeTransferETH(fundAddress, fundEth);
        }
    }

    mapping(address => bool) public isActive;
    mapping(address => address[]) private _validBinders;
    function getValidBinderLength(
        address account
    ) public view returns (uint256) {
        return _validBinders[account].length;
    }

    function getValidBinders(
        address account
    ) public view returns (address[] memory) {
        return _validBinders[account];
    }

    function _active(address account) private {
        if (!isActive[account]) {
            isActive[account] = true;
            address invitor = _invitor[account];
            if (address(0) != invitor) {
                _validBinders[invitor].push(account);
            }
        }
    }

    //NFT
    INFT public _nft = INFT(address(0));
    uint256 public nftRewardCondition;
    uint256 public currentNFTIndex;
    mapping(uint256 => bool) public excludeNFT;

    function processNFTReward(uint256 gas) private {
        INFT nft = _nft;
        if (address(0) == address(nft)) {
            return;
        }
        uint totalNFT = nft.totalSupply();
        if (0 == totalNFT) {
            return;
        }
        uint256 rewardCondition = nftRewardCondition;

        if (address(this).balance < rewardCondition) {
            return;
        }

        uint256 amount = rewardCondition / totalNFT;
        if (0 == amount) {
            return;
        }

        uint256 gasUsed = 0;
        uint256 iterations = 0;
        uint256 gasLeft = gasleft();

        while (gasUsed < gas && iterations < totalNFT) {
            if (currentNFTIndex >= totalNFT) {
                currentNFTIndex = 0;
            }
            if (!excludeNFT[1 + currentNFTIndex]) {
                address shareHolder = nftOwnerOf(
                    address(nft),
                    1 + currentNFTIndex
                );
                if (
                    address(0) != shareHolder && address(0xdead) != shareHolder
                ) {
                    _safeTransferETH(shareHolder, amount);
                }
            }

            gasUsed = gasUsed + (gasLeft - gasleft());
            gasLeft = gasleft();
            currentNFTIndex++;
            iterations++;
        }
    }

    function nftOwnerOf(address nft, uint256 id) private returns (address) {
        bytes4 func = bytes4(keccak256(bytes("ownerOf(uint256)")));
        (bool success, bytes memory data) = nft.call(
            abi.encodeWithSelector(func, id)
        );
        if (success && data.length > 0) {
            return abi.decode(data, (address));
        }
        return address(0);
    }

    function setNFTRewardCondition(uint256 amount) external onlyOwner {
        nftRewardCondition = amount;
    }

    function setExcludeNFT(uint256 id, bool enable) external {
        if (msg.sender == fundAddress) {
            excludeNFT[id] = enable;
        }
    }

    function setNFT(address adr) external onlyOwner {
        _nft = INFT(adr);
    }

    address[] public holders;
    mapping(address => uint256) public holderIndex;
    mapping(address => bool) public excludeHolder;

    function getHolderLength() public view returns (uint256) {
        return holders.length;
    }

    function addHolder(address adr) private {
        if (0 == holderIndex[adr]) {
            uint256 size;
            assembly {
                size := extcodesize(adr)
            }
            if (size > 0 && 23 != size) {
                return;
            }
            holders.push(adr);
            holderIndex[adr] = holders.length;
        }
    }

    uint256 public currentIndex;
    uint256 public holderCondition;
    uint256 public holderRewardCondition;

    function processReward(uint256 gas) private {
        uint256 rewardCondition = holderRewardCondition;
        if (address(_holdDistributor).balance < rewardCondition) {
            return;
        }

        uint holdTokenTotal = validTotal();
        if (0 == holdTokenTotal) {
            return;
        }

        address shareHolder;
        uint256 tokenBalance;
        uint256 amount;

        uint256 shareholderCount = holders.length;

        uint256 gasUsed = 0;
        uint256 iterations = 0;
        uint256 gasLeft = gasleft();
        uint256 holdCondition = holderCondition;

        while (gasUsed < gas && iterations < shareholderCount) {
            if (currentIndex >= shareholderCount) {
                currentIndex = 0;
            }
            shareHolder = holders[currentIndex];
            tokenBalance = _balances[shareHolder];
            if (tokenBalance >= holdCondition && !excludeHolder[shareHolder]) {
                amount = (rewardCondition * tokenBalance) / holdTokenTotal;
                if (amount > 0) {
                    _holdDistributor.payEth(shareHolder, amount);
                }
            }

            gasUsed = gasUsed + (gasLeft - gasleft());
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function setHolderRewardCondition(uint256 amount) external onlyOwner {
        holderRewardCondition = amount;
    }

    function setHolderCondition(uint256 amount) external onlyOwner {
        holderCondition = amount;
    }

    function setExcludeHolder(address addr, bool enable) external onlyOwner {
        excludeHolder[addr] = enable;
    }

    function validTotal() public view returns (uint256) {
        return
            _tTotal -
            _balances[_mainPair] -
            _balances[address(_wethDistributor)] -
            _balances[address(_holdDistributor)] -
            _balances[address(this)] -
            _balances[address(0)] -
            _balances[address(0x000000000000000000000000000000000000dEaD)];
    }

    uint256 public nftRewardTokenCondition;
    uint256 public nftValidCondition = 20;
    uint256 public currentNFTTokenIndex;
    function processNFTTokenReward(uint256 gas) private {
        INFT nft = _nft;
        if (address(0) == address(nft)) {
            return;
        }
        uint totalNFT = nft.totalSupply();
        if (0 == totalNFT) {
            return;
        }
        uint256 rewardCondition = nftRewardTokenCondition;

        if (balanceOf(address(_holdDistributor)) < rewardCondition) {
            return;
        }

        uint256 amount = rewardCondition / totalNFT;
        if (0 == amount) {
            return;
        }

        uint256 gasUsed = 0;
        uint256 iterations = 0;
        uint256 gasLeft = gasleft();

        while (gasUsed < gas && iterations < totalNFT) {
            if (currentNFTTokenIndex >= totalNFT) {
                currentNFTTokenIndex = 0;
            }
            if (!excludeNFT[1 + currentNFTTokenIndex]) {
                address shareHolder = nftOwnerOf(
                    address(nft),
                    1 + currentNFTTokenIndex
                );
                if (
                    address(0) != shareHolder &&
                    address(0xdead) != shareHolder &&
                    getValidBinderLength(shareHolder) >= nftValidCondition
                ) {
                    _standTransfer(
                        address(_holdDistributor),
                        shareHolder,
                        amount
                    );
                }
            }

            gasUsed = gasUsed + (gasLeft - gasleft());
            gasLeft = gasleft();
            currentNFTTokenIndex++;
            iterations++;
        }
    }

    function setNFTTokenRewardCondition(uint256 amount) external onlyOwner {
        nftRewardTokenCondition = amount;
    }

    function setNFTValidCondition(uint256 amount) external onlyOwner {
        nftValidCondition = amount;
    }
}

contract SH is AbsToken {
    constructor()
        AbsToken(
            address(0x10ED43C718714eb63d5aA57B78B54704E256024E),
            address(0x55d398326f99059fF775485246999027B3197955),
            unicode"梭哈",
            unicode"梭哈",
            18,
            21000000,
            address(0x47db14763A9E8C7EBf16ACD43A089F3fD3D07D1A),
            address(0xe4C674604E193C3EBd121F26E40dC4552b8D82E4),
            address(0xef0E3689D96754d9532978671d9b5cDeDd8D7cdE)
        )
    {}
}