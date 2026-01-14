// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {ILAXToken} from "./interface/ILAXToken.sol";
import {ILAXOToken} from "./interface/ILAXOToken.sol";
import {IReferral} from "./interface/IReferral.sol";
import {IProject} from "./interface/IProject.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {_USDT, _ROUTER} from "./Const.sol";
import {IStaking} from "./interface/IStaking.sol";

contract Staking is Owned, IStaking {
    // ============ Constants ============
    uint256 public constant MIN_STAKE_AMOUNT = 1 ether;
    IUniswapV2Router02 constant ROUTER = IUniswapV2Router02(_ROUTER);
    IERC20 constant USDT = IERC20(_USDT);
    uint8 immutable maxD = 100;

    // ============ State Variables ============
    ILAXToken public LAX;
    ILAXOToken public LAXO;
    IReferral public REFERRAL;
    IProject public PROJECT;

    address public QUEUE;

    address public lpAddress;

    Config[3] public configs;

    // ERC20-like properties for display
    uint8 public constant decimals = 18;
    string public constant name = "LAXU";
    string public constant symbol = "LAXU";

    uint256 public totalSupply;
    mapping(address => uint256) public balances;

    mapping(address => Record[]) public userStakeRecord;
    mapping(address => uint256) public teamTotalInvestValue;
    mapping(address => uint256) public teamVirtuallyInvestValue;
    
    mapping(address => bool) public userOneDayStaked;

    // ============ Modifiers ============
    modifier onlyQueue() {
        require(
            msg.sender == QUEUE,
            "only queue or owner"
        );
        _;
    }

    // ============ Constructor ============
    constructor(
        address referral_,
        address project_,
        address lpAddress_
    ) Owned(msg.sender) {
        require(referral_ != address(0), "zero referral");
        require(project_ != address(0), "zero project");
        require(lpAddress_ != address(0), "zero lp address");
        REFERRAL = IReferral(referral_);
        PROJECT = IProject(project_);
        lpAddress = lpAddress_;
        USDT.approve(address(ROUTER), type(uint256).max);

        configs[0] = Config(1000000034670200000, 1 days, 48 hours);
        configs[1] = Config(1000000069236900000, 15 days, 48 hours);
        configs[2] = Config(1000000138062200000, 30 days, 48 hours);
    }
    
    function marketingAddress() public view returns (address) {
        return PROJECT.marketingAddress();
    }
    
    function dividendAddress() public view returns (address) {
        return PROJECT.dividendWallet();
    }
    
    function ecosystemAddress() public view returns (address) {
        return PROJECT.ecosystemAddress();
    }

    // ============ Admin Functions ============
    function setLAX(address _lax) external onlyOwner {
        LAX = ILAXToken(_lax);
        LAX.approve(address(ROUTER), type(uint256).max);
    }

    function setLAXO(address _laxo) external onlyOwner {
        LAXO = ILAXOToken(_laxo);
    }

    function setQueue(address _queue) external onlyOwner {
        QUEUE = _queue;
    }

    function setTeamVirtuallyInvestValue(
        address _user,
        uint256 _value
    ) external onlyOwner {
        teamVirtuallyInvestValue[_user] = _value;
    }

    function setProject(address _project) external onlyOwner {
        require(_project != address(0), "zero address");
        PROJECT = IProject(_project);
    }

    function setLpAddress(address _lpAddress) external onlyOwner {
        require(_lpAddress != address(0), "zero address");
        lpAddress = _lpAddress;
    }

    // ============ Core Staking Functions (Called by Queue) ============

    function stakeFor(address user, uint160 amount, uint8 stakeIndex) external onlyQueue {
        require(amount >= MIN_STAKE_AMOUNT, ">=MIN_STAKE_AMOUNT");
        require(stakeIndex < configs.length, "index out of range");
        require(REFERRAL.isBindReferral(user), "!!bind");
        
        if (stakeIndex == 0) {
            require(!userOneDayStaked[user], "1day already staked");
            userOneDayStaked[user] = true;
        }

        _swapAndAddLiquidity(amount);
        _mint(user, amount, stakeIndex);
    }

    function unstakeFor(
        address user,
        uint256 index
    ) external onlyQueue returns (uint256 actualAmount) {
        uint256 amount;
        (, amount, actualAmount) = _burn(user, index);

        address[] memory referrals = REFERRAL.getReferrals(user, maxD);
        for (uint8 i = 0; i < referrals.length; i++) {
            teamTotalInvestValue[referrals[i]] -= amount;
        }

        if (actualAmount == 0) {
            return 0;
        }
        (uint256 amount_usdt, uint256 amount_lax) = _swapLAXForExactUSDT(
            actualAmount
        );

        USDT.transfer(user, amount_usdt);
        LAX.recycle(amount_lax);
    }

    function restakeFor(address user, uint256 _index, uint160 _amount, uint8 _stakeIndex) external onlyQueue {
        require(_amount >= MIN_STAKE_AMOUNT, ">=MIN_STAKE_AMOUNT");
        require(_stakeIndex < configs.length, "index out of range");
        require(_stakeIndex > 0, "restake cannot be 1day");

        Record storage user_record = userStakeRecord[user][_index];
        require(user_record.unstakeTime > 0, "not unstaked");
        require(user_record.restakeTime == 0, "already restaked");
        require(_amount >= user_record.amount, "amount too small");
        require(_stakeIndex >= user_record.stakeIndex, "stake index too small");

        _swapAndAddLiquidity(_amount);
        
        user_record.restakeTime = uint40(block.timestamp);
        _mint(user, _amount, _stakeIndex);

        emit Restaked(user, uint40(block.timestamp), _index);
    }

    function claimFor(address user, uint256 _index) external onlyQueue {
        Record storage user_record = userStakeRecord[user][_index];
        require(user_record.reward > 0, "no reward");
        Config memory config = configs[user_record.stakeIndex];
        require(
            user_record.restakeTime > 0 &&
                user_record.restakeTime <= user_record.unstakeTime + config.ttl,
            "not restaked in time"
        );

        uint160 claimReward = user_record.reward;
        user_record.reward = 0;

        _distributeReward(user, claimReward);

        emit RewardPaid(
            user,
            claimReward,
            uint40(block.timestamp),
            _index
        );
    }

    // ============ View Functions ============

    function balanceOf(
        address account
    ) external view returns (uint256 balance) {
        Record[] storage cord = userStakeRecord[account];
        if (cord.length > 0) {
            for (uint256 i = cord.length - 1; i >= 0; i--) {
                Record storage user_record = cord[i];
                if (user_record.unstakeTime == 0) {
                    balance += _caclItem(user_record);
                }
                if (i == 0) break;
            }
        }
    }

    function rewardOfSlot(
        address user,
        uint8 index
    ) public view returns (uint256 reward) {
        Record storage user_record = userStakeRecord[user][index];
        return _caclItem(user_record);
    }

    function stakeCount(address user) external view returns (uint256 count) {
        count = userStakeRecord[user].length;
    }

    function getTeamKpi(address _user) public view returns (uint256) {
        return teamTotalInvestValue[_user] + teamVirtuallyInvestValue[_user];
    }

    function isPreacher(address user) public view returns (bool) {
        return balances[user] >= 199 ether;
    }

    function getStakeRecord(
        address user,
        uint256 index
    ) external view returns (Record memory) {
        return userStakeRecord[user][index];
    }

    // ============ Internal Functions ============

    function _mint(address sender, uint160 _amount, uint8 _stakeIndex) private {
        Record memory order;
        order.stakeTime = uint40(block.timestamp);
        order.amount = _amount;
        order.stakeIndex = _stakeIndex;

        totalSupply += _amount;
        balances[sender] += _amount;
        Record[] storage cord = userStakeRecord[sender];
        uint256 stake_index = cord.length;
        cord.push(order);

        address[] memory referrals = REFERRAL.getReferrals(sender, maxD);
        for (uint8 i = 0; i < referrals.length; i++) {
            teamTotalInvestValue[referrals[i]] += _amount;
        }

        emit Transfer(address(0), sender, _amount);
        emit Staked(
            sender,
            _amount,
            uint40(block.timestamp),
            stake_index,
            configs[_stakeIndex].day
        );
    }

    function _burn(
        address sender,
        uint256 index
    ) private returns (uint256 reward, uint256 amount, uint256 actualAmount) {
        Record[] storage cord = userStakeRecord[sender];
        Record storage user_record = cord[index];

        uint256 stakeTime = user_record.stakeTime;
        Config memory config = configs[user_record.stakeIndex];
        uint256 maturityTime = stakeTime + config.day;
        
        require(block.timestamp >= maturityTime, "The time is not right");
        require(user_record.unstakeTime == 0, "alw");

        amount = user_record.amount;
        
        uint256 penaltyRate = _calcPenaltyRate(maturityTime);
        actualAmount = (amount * (100 - penaltyRate)) / 100;
        
        totalSupply -= amount;
        balances[sender] -= amount;
        emit Transfer(sender, address(0), amount);

        reward = _caclItem(user_record);
        user_record.unstakeTime = uint40(block.timestamp);
        if (reward > amount) {
            user_record.reward = uint160(reward - amount);
        }

        emit Unstaked(
            sender,
            uint160(actualAmount),
            uint40(block.timestamp),
            index,
            user_record.reward,
            config.ttl
        );
    }

    function _calcPenaltyRate(uint256 maturityTime) private view returns (uint256 penaltyRate) {
        if (block.timestamp <= maturityTime) {
            return 0;
        }
        
        uint256 delayTime = block.timestamp - maturityTime;
        uint256 penaltyPeriods = delayTime / 24 hours;
        
        penaltyRate = penaltyPeriods * 5;
        if (penaltyRate > 100) {
            penaltyRate = 100;
        }
    }

    function _caclItem(
        Record storage user_record
    ) private view returns (uint256 reward) {
        UD60x18 stake_amount = ud(user_record.amount);
        uint40 stake_time = user_record.stakeTime;
        uint40 stake_period = (uint40(block.timestamp) - stake_time);
        stake_period = Math.min(
            stake_period,
            configs[user_record.stakeIndex].day
        );
        if (stake_period == 0) reward = UD60x18.unwrap(stake_amount);
        else
            reward = UD60x18.unwrap(
                stake_amount.mul(
                    ud(configs[user_record.stakeIndex].rate).powu(stake_period)
                )
            );
    }

    function _distributeReward(address _user, uint160 _reward) private {
        (uint256 amount_usdt, uint256 swapped_lax) = _swapLAXForExactUSDT(
            _reward
        );

        uint256 laxo_amount = (amount_usdt * 50) / 1000;
        _buyLaxoToTarget(laxo_amount);

        uint256 team_reward_amount = (amount_usdt * 350) / 1000;
        _teamReward(_user, team_reward_amount);

        uint256 user_amount = amount_usdt - laxo_amount - team_reward_amount;
        USDT.transfer(_user, user_amount);

        LAX.recycle(swapped_lax);
    }

    function _buyLaxoToTarget(uint256 _usdtAmount) private {
        if (_usdtAmount == 0) return;
        if (address(LAXO) != address(0) && LAXO.isReachedMaxBurn()) {
            USDT.transfer(ecosystemAddress(), _usdtAmount);
        } else {
            _swapExactUSDTForLAXO(_usdtAmount,dividendAddress());
        }
    }

    function _teamReward(
        address _user,
        uint256 _totalReward
    ) private returns (uint256 spentAmount) {
        address[] memory referrals = REFERRAL.getReferrals(_user, maxD);
        address top_team;
        uint256 team_kpi;
        uint256 maxTeamRate = 35;
        uint256 spendRate = 0;

        for (uint256 i = 0; i < referrals.length; i++) {
            top_team = referrals[i];
            team_kpi = getTeamKpi(top_team);

            if (
                team_kpi >= 30000000 * 10 ** 18 &&
                maxTeamRate > spendRate &&
                isPreacher(top_team)
            ) {
                USDT.transfer(
                    top_team,
                    (_totalReward * (maxTeamRate - spendRate)) / maxTeamRate
                );
                spendRate = 35;
            }

            if (
                team_kpi >= 10000000 * 10 ** 18 &&
                team_kpi < 30000000 * 10 ** 18 &&
                spendRate < 32 &&
                isPreacher(top_team)
            ) {
                USDT.transfer(top_team, (_totalReward * (32 - spendRate)) / maxTeamRate);
                spendRate = 32;
            }

            if (
                team_kpi >= 5000000 * 10 ** 18 &&
                team_kpi < 10000000 * 10 ** 18 &&
                spendRate < 29 &&
                isPreacher(top_team)
            ) {
                USDT.transfer(top_team, (_totalReward * (29 - spendRate)) / maxTeamRate);
                spendRate = 29;
            }

            if (
                team_kpi >= 1000000 * 10 ** 18 &&
                team_kpi < 5000000 * 10 ** 18 &&
                spendRate < 26 &&
                isPreacher(top_team)
            ) {
                USDT.transfer(top_team, (_totalReward * (26 - spendRate)) / maxTeamRate);
                spendRate = 26;
            }

            if (
                team_kpi >= 500000 * 10 ** 18 &&
                team_kpi < 1000000 * 10 ** 18 &&
                spendRate < 22 &&
                isPreacher(top_team)
            ) {
                USDT.transfer(top_team, (_totalReward * (22 - spendRate)) / maxTeamRate);
                spendRate = 22;
            }

            if (
                team_kpi >= 100000 * 10 ** 18 &&
                team_kpi < 500000 * 10 ** 18 &&
                spendRate < 18 &&
                isPreacher(top_team)
            ) {
                USDT.transfer(top_team, (_totalReward * (18 - spendRate)) / maxTeamRate);
                spendRate = 18;
            }

            if (
                team_kpi >= 50000 * 10 ** 18 &&
                team_kpi < 100000 * 10 ** 18 &&
                spendRate < 13 &&
                isPreacher(top_team)
            ) {
                USDT.transfer(top_team, (_totalReward * (13 - spendRate)) / maxTeamRate);
                spendRate = 13;
            }

            if (
                team_kpi >= 10000 * 10 ** 18 &&
                team_kpi < 50000 * 10 ** 18 &&
                spendRate < 7 &&
                isPreacher(top_team)
            ) {
                USDT.transfer(top_team, (_totalReward * (7 - spendRate)) / maxTeamRate);
                spendRate = 7;
            }
        }
        
        spentAmount = (_totalReward * spendRate) / maxTeamRate;
        
        if (maxTeamRate > spendRate) {
            USDT.transfer(
                marketingAddress(),
                _totalReward - spentAmount
            );
        }
    }

    // ============ Swap Functions ============

    function _swapAndAddLiquidity(uint160 _amount) private {
        USDT.transferFrom(msg.sender, address(this), _amount);
        uint256 amount_lax = _swapExactUSDTForLAX(_amount / 2);
        ROUTER.addLiquidity(
            address(USDT),
            address(LAX),
            _amount / 2,
            amount_lax,
            0,
            0,
            lpAddress,
            block.timestamp
        );
    }

    function _swapLAXForExactUSDT(
        uint256 _usdtAmount
    ) private returns (uint256 amount_usdt, uint256 amount_lax) {
        uint256 bal_this = LAX.balanceOf(address(this));
        uint256 usdt_this = USDT.balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(LAX);
        path[1] = address(USDT);
        ROUTER.swapTokensForExactTokens(
            _usdtAmount,
            bal_this,
            path,
            address(this),
            block.timestamp
        );
        uint256 bal_now = LAX.balanceOf(address(this));
        uint256 usdt_now = USDT.balanceOf(address(this));
        amount_lax = bal_this - bal_now;
        amount_usdt = usdt_now - usdt_this;
    }

    function _swapExactUSDTForLAX(
        uint256 _usdtAmount
    ) private returns (uint256 amount_lax) {
        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(LAX);
        uint256 balb = LAX.balanceOf(address(this));
        ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _usdtAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
        uint256 bala = LAX.balanceOf(address(this));
        amount_lax = bala - balb;
    }

    function _swapExactUSDTForLAXO(
        uint256 _usdtAmount,
        address _to
    ) private {
        address[] memory path = new address[](2);
        path[0] = address(USDT);
        path[1] = address(LAXO);
        ROUTER.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _usdtAmount,
            0,
            path,
            _to,
            block.timestamp
        );
    }
    // ============ Emergency Functions ============

    function sync() external {
        require(msg.sender == owner || msg.sender == marketingAddress(), "!owner or marketing");
        uint256 w_bal = IERC20(USDT).balanceOf(address(this));
        address pair = LAX.uniswapV2Pair();
        IERC20(USDT).transfer(pair, w_bal);
        IUniswapV2Pair(pair).sync();
    }

    function emergencyWithdrawLAX(
        address to,
        uint256 _amount
    ) external onlyOwner {
        LAX.transfer(to, _amount);
    }
}

library Math {
    function min(uint40 a, uint40 b) internal pure returns (uint40) {
        return a < b ? a : b;
    }

    function min256(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}