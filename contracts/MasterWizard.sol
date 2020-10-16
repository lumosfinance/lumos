// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./common/IERC20.sol";
import "./common/SafeERC20.sol";
import "./common/EnumerableSet.sol";
import "./common/Ownable.sol";
import "./LumosToken.sol";
import "./common/IUniswapV2Pair.sol";
import "./common/UniswapV2OracleLibrary.sol";
import "./common/IMakerPriceFeed.sol";
import "./common/DSMath.sol";

// Grand Master is the wisest and oldest Wizard of lumos. He now governs over LUMOS. He can craft LMS, however he's wise and helpful so he lets adventurers 
//craft LMS while they learn casting spells. He will guide you all in all fairness. 
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once the key ingredient LMS is sufficiently
// distributed and the community can show to govern itself in peace. 
//
// Have fun reading it. Hopefully it's bug-free. May the magic be with you.
contract MasterWizard is Ownable {
    using DSMath for uint;
    using SafeERC20 for IERC20;

    // Info of each adventurer.
    struct UserInfo {
        uint amount; // How many LP tokens the adventurer has provided.
        uint rewardDebt; // Reward debt. See explanation below.
        uint lastHarvestBlock;
        uint totalHarvestReward;
        //
        // We do some fancy math here. Basically, any point in time, the amount of LMS
        // entitled to an adventurer but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLumosPerShare) - user.rewardDebt
        //
        // Whenever an adventurer deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLumosPerShare` (and `lastRewardBlock`) gets updated.
        //   2. Adventurer receives the pending reward sent to his/her address.
        //   3. Adventurer's `amount` gets updated.
        //   4. Adventurer's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint allocPoint; // How many allocation points assigned to this pool. LMS to distribute per block.
        uint lastRewardBlock; // Last block number that LMS distribution occurs.
        uint accLumosPerShare; // Accumulated LMS per share, times 1e6. See below.
    }

    // The LUMOS TOKEN!
    LumosToken public lumos;
    // Dev fund (2%, initially)
    uint public devFundDivRate = 50 * 1e18; //Wizards casting spells while teaching so some LMS is created. These will be used wisely to develop Lumos. 
    // Dev address.
    address public devaddr;
    // LUMOS tokens created per block.
    uint public lumosPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    mapping(address => uint256) public poolId1; // poolId1 count from 1, subtraction 1 before using with poolInfo

    // Info of each user that stakes LP tokens.
    mapping(uint => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint public totalAllocPoint = 0;
    // The block number when LMS mining starts.
    uint public startBlock;

    //uint public endBlock;
    uint public startBlockTime;

    /// @notice pair for reserveToken <> LMS
    address public uniswap_pair;

    /// @notice last TWAP update time
    uint public blockTimestampLast;

    /// @notice last TWAP cumulative price;
    uint public priceCumulativeLast;

    /// @notice Whether or not this token is first in uniswap LMS<>Reserve pair
    bool public isToken0;

    uint public lmsPriceMultiplier;

    uint public minLMSTWAPIntervalSec;

    address public makerEthPriceFeed;

    uint public timeOfInitTWAP;

    bool public testMode;

    bool public farmEnded;

    // Events
    event Recovered(address token, uint amount);
    event Deposit(address indexed user, uint indexed pid, uint amount);
    event Withdraw(address indexed user, uint indexed pid, uint amount);
    event EmergencyWithdraw(
        address indexed user,
        uint indexed pid,
        uint amount
    );

    constructor(
        LumosToken _lumos,
        address reserveToken_,//WETH
        address _devaddr,
        uint _startBlock,
        bool _testMode
    ) public {
        lumos = _lumos;
        devaddr = _devaddr;
        startBlock = _startBlock;

        (address _uniswap_pair, bool _isToken0) = UniswapV2OracleLibrary.getUniswapV2Pair(address(lumos),reserveToken_);

        uniswap_pair = _uniswap_pair;
        isToken0 = _isToken0;

        makerEthPriceFeed = 0x729D19f657BD0614b4985Cf1D82531c67569197B;

        lmsPriceMultiplier = 0;
        testMode = _testMode;
        
         if(testMode == true) {
            minLMSTWAPIntervalSec = 1 minutes;
         }
         else {
            minLMSTWAPIntervalSec = 23 hours;
         }
    }

    function poolLength() external view returns (uint) {
        return poolInfo.length;
    }

    function start_crafting() external onlyOwner {
        require(block.number > startBlock, "not this time.!");
        require(startBlockTime == 0, "already started.!");

        startBlockTime = block.timestamp;

        lumosPerBlock = getLumosPerBlock();
        lmsPriceMultiplier = 1e18;
    }
   function end_crafting() external onlyOwner 
    {
        require(startBlockTime > 0, "not started.!");

        if(lumos.totalSupply() > (1e18 * 2000000)) {
            farmEnded = true;
        }

    }
    function init_TWAP() external onlyOwner {
        require(timeOfInitTWAP == 0,"already initialized.!");
        (uint priceCumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(uniswap_pair, isToken0);

        require(blockTimestamp > 0, "no trades");

        blockTimestampLast = blockTimestamp;
        priceCumulativeLast = priceCumulative;
        timeOfInitTWAP = blockTimestamp;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner {
        require(poolId1[address(_lpToken)] == 0, "add: lp is already in pool");

        if (_withUpdate) {
            massUpdatePools();
        }
        _allocPoint = _allocPoint.toWAD18();

        uint lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolId1[address(_lpToken)] = poolInfo.length + 1;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accLumosPerShare: 0
            })
        );
    }

    // Update the given pool's LMS allocation point. Can only be called by the owner.
    function set(
        uint _pid,
        uint _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        _allocPoint = _allocPoint.toWAD18();

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }
     //Updates the price of LMS token
    function getTWAP() private returns (uint) {

        (uint priceCumulative,uint blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(uniswap_pair, isToken0);
        
        uint timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulative - priceCumulativeLast) / timeElapsed)
        );

        priceCumulativeLast = priceCumulative;
        blockTimestampLast = blockTimestamp;

        return FixedPoint.decode144(FixedPoint.mul(priceAverage, 10**18));
    }
    function getCurrentTWAP() external view returns (uint) {

        (uint priceCumulative,uint blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(uniswap_pair, isToken0);
        
        uint timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112(
            uint224((priceCumulative - priceCumulativeLast) / timeElapsed)
        );

        return FixedPoint.decode144(FixedPoint.mul(priceAverage, 10**18));
    }
    //Updates the ETHUSD price to calculate LMS price in USD. 
    function getETHUSDPrice() public view returns(uint) {
        if(testMode){
            return 384.2e18;
        }
        return uint(IMakerPriceFeed(makerEthPriceFeed).read());
    }
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint _from, uint _to) private view returns (uint) {
        //require(startBlockTime > 0, "farming not activated yet.!");
        uint _blockCount = _to.sub(_from);
        return lumosPerBlock.wmul(lmsPriceMultiplier).mul(_blockCount);//.wdiv(1 ether);
    }

    // View function to see pending LMS on frontend.
    function pendingLumos(uint _pid, address _user)
        external
        view
        returns (uint)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint accLumosPerShare = pool.accLumosPerShare;
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint multiplier = getMultiplier(
                pool.lastRewardBlock,
                block.number
            );
            uint lumosReward = multiplier
            //.mul(lumosPerBlock)
                .wmul(pool.allocPoint)
                .wdiv(totalAllocPoint);
                //.wdiv(1e18);
            accLumosPerShare = accLumosPerShare.add(
                lumosReward
                //.mul(1e6)
                .wdiv(lpSupply)
            );
        }
        return user.amount.wmul(accLumosPerShare)
        //.div(1e12)
        .sub(user.rewardDebt);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        
        if(farmEnded){
            return;
        }

        uint multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint lmsReward = multiplier
        //.mul(lumosPerBlock)
            .wmul(pool.allocPoint)
            .wdiv(totalAllocPoint);
            //.wdiv(1e18);
        lumos.mint(devaddr, lmsReward.wdiv(devFundDivRate));
        lumos.mint(address(this), lmsReward);
        pool.accLumosPerShare = pool.accLumosPerShare.add(
            lmsReward
            //.mul(1e12)
            .wdiv(lpSupply)
        );
        pool.lastRewardBlock = block.number;

        //setLMSPriceMultiplierInt();
    }

    // Deposit LP tokens to MasterWizard for LMS allocation.
    function deposit(uint _pid, uint _amount) public {
        require(startBlockTime > 0, "farming not activated yet.!");
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint pending = user
                .amount
                .wmul(pool.accLumosPerShare)
                //.div(1e12)
                .sub(user.rewardDebt);
            if (pending > 0) {
                uint _harvestMultiplier = getLumosHarvestMultiplier(
                    user.lastHarvestBlock
                );

                uint _harvestBonus = pending.wmul(_harvestMultiplier);

                // With magic, Grand Master rewards adventurer if she chooses to let their rewards stays in the Crafting Pool.    
                if (_harvestBonus > 1e18) {
                    lumos.mint(msg.sender, _harvestBonus);
                    user.totalHarvestReward = user.totalHarvestReward.add(
                        _harvestBonus
                    );
                }
                safeLMSTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.amount = user.amount.add(_amount);
        }
        user.lastHarvestBlock = block.number;
        user.rewardDebt = user.amount.wmul(pool.accLumosPerShare);
        //.div(1e12);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterWizard.
    function withdraw(uint _pid, uint _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint pending = user.amount.wmul(pool.accLumosPerShare)
        //.div(1e12)
        .sub(user.rewardDebt);

        if (pending > 0) {
            safeLMSTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.wmul(pool.accLumosPerShare);//.div(1e12);

        user.lastHarvestBlock = block.number;

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.lastHarvestBlock = block.number;
        // user.withdrawalCount++;
    }

    // Safe lumos transfer function, just in case if rounding error causes pool to not have enough LMS.
    function safeLMSTransfer(address _to, uint _amount) private {
        uint lmsBalance = lumos.balanceOf(address(this));
        if (_amount > lmsBalance) {
            lumos.transfer(_to, lmsBalance);
        } else {
            lumos.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    //function dev(address _devaddr) public {
    //    require(msg.sender == devaddr, "dev: wut?");
    //    devaddr = _devaddr;
    //}

    function setStartBlockTime(uint _startBlockTime) external {
        require(testMode, "testing or not ?");

        startBlockTime = _startBlockTime;
    }
    function setLMSPriceMultiplier(uint _multiplier) external {
        require(testMode, "testing or not ?");

        lmsPriceMultiplier = _multiplier * 1e18;
    }
    function getLumosTotalSupply() external view returns(uint) {
        require(testMode, "testing or not ?");

        return lumos.totalSupply();
    }

    // Community casting this spell every day and decides the daily bonus multiplier for the next day. This spell can be cast only once in every day. 
    function setLMSPriceMultiplier() external {
        require(startBlockTime > 0 && blockTimestampLast.add(minLMSTWAPIntervalSec) < now, "not this time.!");
        require(timeOfInitTWAP > 0, "farm not initialized.!");
        require(farmEnded == false, "farm ended :(");
        
        setLMSPriceMultiplierInt();
    }
    function setLMSPriceMultiplierInt() private {
        if(startBlockTime == 0 || blockTimestampLast.add(minLMSTWAPIntervalSec) > now || timeOfInitTWAP == 0 || farmEnded == true) {
            return;
        }
        uint _lmsPriceETH = getTWAP();
        uint _ethPriceUSD = getETHUSDPrice();
        uint _price = _lmsPriceETH.wmul(_ethPriceUSD);

        if (_price < 1.5e18) 
            lmsPriceMultiplier = 1e18;
        else if (_price >= 1.5e18 && _price < 2.5e18)
            lmsPriceMultiplier = 2e18; 
        else if (_price >= 2.5e18 && _price < 5e18)
            lmsPriceMultiplier = 3e18;
        else lmsPriceMultiplier = 4e18;

        lumosPerBlock = getLumosPerBlock();
    }

    // lumos per block multiplier
    function getLumosPerBlock() private view returns (uint) {
        uint elapsedDays = ((now - startBlockTime).div(86400) + 1) * 1e6;
        return elapsedDays.sqrt().wdiv(6363);
    }

    // harvest multiplier
    function getLumosHarvestMultiplier(uint _lastHarvestBlock) private view returns (uint) {
        return
            (block.number - _lastHarvestBlock).wdiv(67000).min(1e18);
    }

    function setDevFundDivRate(uint _devFundDivRate) external onlyOwner {
        require(_devFundDivRate > 0, "dev fund rate 0 ?");
        devFundDivRate = _devFundDivRate;
    }

    function setminLMSTWAPIntervalSec(uint _interval) external onlyOwner {
        require(_interval > 0, "minLMSTWAPIntervalSec 0 ?");
        minLMSTWAPIntervalSec = _interval;
    }    
}
