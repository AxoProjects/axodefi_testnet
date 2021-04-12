// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./libs/Constants.sol";
import "./libs/IMasterChef.sol";
import "./libs/IRewardPool.sol";
import "./LotlToken.sol";

//CHANGE FOR BSC
//import "./libs/IBEP20.sol";
//import "./libs/SafeBEP20.sol";
//import "./libs/IRewardPool.sol";

// Forkend and modified from GooseDefi code:
// https://github.com/goosedefi/goose-contracts/blob/master/contracts/MasterChefV2.sol
// MasterChef is the master of Lotl. He can make Lotl and he is a fair guy.
// Note that it's ownable and the owner can start the minting once, halve the emission rate and add pools.
// Have fun reading it. Hopefully it's bug-free. Satan bless.

contract MasterChef is Ownable, ReentrancyGuard, IMasterChef, Constants {
    //using SafeBEP20 for IBEP20;
    //CHANGE FOR BSC
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint128 amount;                 // How many LP tokens the user has provided.
        uint128 rewardDebt;             // Reward debt. See explanation below.
        uint32 stakedSince;            // Weighted block.number since last stake.  
    }

        //
        // We do some fancy math here. Basically, any point in time, the amount of LOTLs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accLotlPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accLotlPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
        //
        // In addition to that we do even more fancy stuff here, to calculate the distribution of our 7 day reward pool.
        //  1. First of, we reserve 30% of all minted LOTL to our reward pool. ('pendingRewardLotl')
        //  2. We send 90% of all taxes paid to our RewardPool contract.
        //  3. All fees will be swapped to BUSD and sent back to the MasterChef contract.
        //  4. Then we use calculateRewardPool to calculate all rewards per share for each user and sum them up for each user across all pools the user staked in.
        //  5. for all pools rewardPerShare += rewardPerShare + adjustedUserAmount / adjustedPoolLiquidity * pool.allocPoint / totalAllocPoints  
        //  6. Then to get your actual reward you need to withdraw your rewards before the next reward pool is distributed or else they will be used for the next reward pool.
        //  7. Rewards are paid out in the function 'withdrawRewards' and are finally calculated as follows.
        //  8. reward = totalRewardPool * user.rewardPoolShare

        // Time based holding factor:
        // Calculated by making use of the transaction blocks. 
        // Block since last deposit event is saved
        // Deposit/Withdraw event modifier your transaction blocks.
        // After your initial deposit your block number is updatet with following equation:
        // user.stakedSince = user.stakedSince + (block.number - user.stakedSince) * taxedAmount / (user.amount + taxedAmount);
        // Withdrawin any amount >0 resets your block number to the current transaction block.
     
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.
        uint8 allocPoint;           // How many allocation points assigned to this pool. LOTLs to distribute per block.
        uint32 lastRewardBlock;    // Last block number that LOTLs distribution occurs.
        uint128 accLotlPerShare;    // Accumulated LOTLs per share, times 1e12. See below.
        uint16 depositFeeBP;        // Deposit fee in basis points.
        uint16 unstakingFeeBP;      // Unstaking fee in basis points.
        address []poolUser;         // Addresses of all stakes in pool.
        uint16 totalUserStaked;    // Amount of current number of stakes in pool.
        bool isLPPool;              // LP flag.
    }

    // Info for the reward pool.
    // All rewards that haven't been claimed until the next reward distribution will be nulled and added to the next distribution. 
    struct Rewards {
        uint128 amountBUSD;         // BUSD to distribute among all stakers.
        uint128 amountLOTL;         // LOTL to distribute among all stakers.
        uint128 remainingLOTL;      // Remainder of LOTL.
        address []poolUser;         // Addresses of all distinct stakes across all pools.
    }    

    // Lotl to allocate to reward pool.
    uint128 public pendingRewardLotl; 
    
    // Info of reward pool.
    Rewards public rewardInfo;

    // The LOTL TOKEN!
    LotlToken public lotl;

    // Dev address.
    address public devAddr;

    // RewardPool address.
    IRewardPool public rewardPool;

    
    // LOTL tokens created per block.
    uint64 public lotlPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of the allocated rewardPoolShare per user
    mapping(uint16 => mapping(address => uint128)) public rewardPoolShare;
    
    // Info of each user that stakes LP tokens.
    mapping(uint8 => mapping(address => UserInfo)) public userInfo;

    // Info wether a user has already staked in the platform;
    mapping(uint8 => mapping(address => bool)) public userExists;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint16 public totalAllocPoint = 0;

    // Indicator of the current reward pool iteration.
    uint16 public currentRewardIteration = 1;

    event Deposit(address indexed user, uint8 indexed pid, uint128 amount);
    event Withdraw(address indexed user, uint8 indexed pid, uint128 amount);
    event WithdrawReward(address indexed user, uint128 amountLotl, uint128 amountBUSD);
    event EmergencyWithdraw(address indexed user, uint8 indexed pid, uint128 amount);
    event SetRewardAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateMintingRate(address indexed user, uint64 lotlPerBlock);
    
    constructor(LotlToken _lotl) public {
        lotl = _lotl;
        devAddr = msg.sender;
        rewardPool = IRewardPool(msg.sender);
    }

    // Used to determine wether a pool has already been added.
    mapping(IERC20 => bool) public poolExistence;

    // Modifier to allow only new pools being added.
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint8 _allocPoint, IERC20 _lpToken, IERC20 _tokenA, IERC20 _tokenB, uint16 _depositFeeBP, uint16 _unstakingFeeBP, bool _withUpdate, bool _isLPPool) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");

        require (_allocPoint <= 100, "add: invalid allocation points");
        
        if (_withUpdate) {
            massUpdatePools();
        }
        if(_isLPPool)
        {
            rewardPool.addLpToken(_lpToken, _tokenA, _tokenB, _isLPPool);
        }
        else
        {
            rewardPool.addLpToken(_lpToken, _lpToken, _lpToken, _isLPPool);
        }
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolExistence[_lpToken] = true;
        PoolInfo memory poolToAdd;
        poolToAdd.lpToken = _lpToken;
        poolToAdd.allocPoint =  _allocPoint;
        poolToAdd.lastRewardBlock = uint32(block.number);
        poolToAdd.depositFeeBP =  _depositFeeBP;
        poolToAdd.unstakingFeeBP = _unstakingFeeBP;
        poolToAdd.isLPPool = _isLPPool;
        poolInfo.push(poolToAdd);
    }

    // View function to see pending LOTLs on frontend.
    function pendingLotl(uint8 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint32 currentBlock = uint32(block.number);
        uint256 accLotlPerShare = pool.accLotlPerShare;
        uint128 lpSupply = uint128(pool.lpToken.balanceOf(address(this)));
        if (currentBlock > pool.lastRewardBlock && lpSupply != 0) {
            uint128 lotlReward =  lotlPerBlock * uint128((currentBlock - pool.lastRewardBlock) * pool.allocPoint  / totalAllocPoint);
            accLotlPerShare = accLotlPerShare + lotlReward * 1e12 / lpSupply;
        }
        return user.amount * accLotlPerShare / 1e12 - user.rewardDebt;
    }

    // View function to see pending rewards on frontend.
    function pendingRewards(address _user) external view returns (uint128 _lotl, uint128 _busd) {
        uint128 share = rewardPoolShare[currentRewardIteration-1][_user];
        if(share > 0){
        uint128 busdPending = rewardInfo.amountBUSD * share / 1e12;
        uint128 lotlPending = rewardInfo.amountLOTL * share / 1e12;
        return (lotlPending, busdPending);
        }
        else{
            return (0,0);
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint8 length = uint8(poolInfo.length);
        for (uint8 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // 14400 blocks = 1 time factor
    function calculateTimeRewards (uint32 _stakedSince) public view returns (uint32)  {
        /*
        uint32 timeFactor = (uint32(block.number) - _stakedSince) / 14400;
        if(timeFactor == 0){
            return 1;
        }
        else{
            return timeFactor;
        }
        */
        //testing
        return uint32(block.number) - _stakedSince;
    } 

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint8 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint32 currentBlock = uint32(block.number);
        if (currentBlock <= pool.lastRewardBlock) {
            return;
        }

        uint128 lpSupply = uint128(pool.lpToken.balanceOf(address(this)));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = currentBlock;
            return;
        }

        if(lotlPerBlock == 0){
            pool.lastRewardBlock = currentBlock;
            return;
        }

        uint128 lotlReward = lotlPerBlock * uint128((currentBlock - pool.lastRewardBlock) * pool.allocPoint / totalAllocPoint);
        lotl.mint(devAddr, lotlReward / 10);
        pendingRewardLotl = pendingRewardLotl + lotlReward / 10 * 3;
        lotl.mint(address(this), lotlReward - lotlReward / 10);
        lotlReward = lotlReward - (lotlReward / 10 * 4);
        pool.accLotlPerShare = pool.accLotlPerShare + lotlReward * 1e12 / lpSupply;
        pool.lastRewardBlock = currentBlock;
    }

    // Deposit LP tokens to MasterChef for LOTL allocation.
    function deposit(uint8 _pid, uint128 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint32 currentBlock = uint32(block.number);
        // Save last block number as staking timestamp
        if (user.stakedSince == 0 && _amount > 0){
            user.stakedSince = currentBlock;
        }
        if (user.amount > 0) {
            uint256 pending = user.amount * pool.accLotlPerShare / 1e12 - user.rewardDebt;
            if (pending > 0) {
                lotl.transfer(msg.sender, pending);
            }
        } 
        if (_amount > 0) {
            pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
            uint128 taxedAmount = _amount * (1e4 - pool.depositFeeBP) / 1e4;
            // Holding factor scaling
            if(user.amount > 0){
                user.stakedSince = uint32(user.stakedSince +  taxedAmount * (currentBlock - user.stakedSince)  / (user.amount + taxedAmount));

            }
            if(!userExists[_pid+1][msg.sender]){
                pool.poolUser.push(msg.sender);
                userExists[_pid+1][msg.sender] = true;
            }
             if(!userExists[0][msg.sender]){
                rewardInfo.poolUser.push(msg.sender);
                userExists[0][msg.sender] = true;
            }
            if (pool.depositFeeBP > 0) {
                uint128 depositFee = _amount - taxedAmount;
                pool.lpToken.transfer(devAddr, depositFee / 10);
                depositFee = depositFee - depositFee / 10;
                pool.lpToken.transfer(address(rewardPool), depositFee);
                if(pool.isLPPool){
                    rewardPool.removeLiquidityExternal(pool.lpToken, depositFee);
                }
                else{
                    rewardPool.swapToBusdExternal(pool.lpToken, depositFee);
                }
            } 
            user.amount = user.amount + taxedAmount;   
        }
        user.rewardDebt = user.amount * pool.accLotlPerShare / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint8 _pid, uint128 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint32 currentBlock = uint32(block.number);
        uint128 pending = user.amount * pool.accLotlPerShare / 1e12 - user.rewardDebt;
        if (pending > 0) {
            lotl.transfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount - _amount;
            uint128 taxedAmount = _amount;
            if(pool.unstakingFeeBP > 0 && calculateTimeRewards(user.stakedSince) < 14){
                taxedAmount = _amount * (1e4 - pool.unstakingFeeBP) / 1e4;
                uint128 unstakingFee = _amount - taxedAmount;
                pool.lpToken.transfer(devAddr, unstakingFee / 10);
                unstakingFee = unstakingFee - unstakingFee / 10;
                pool.lpToken.transfer(address(rewardPool), unstakingFee);
                if(pool.isLPPool){
                    rewardPool.removeLiquidityExternal(pool.lpToken, unstakingFee);
                }
                else{
                    rewardPool.swapToBusdExternal(pool.lpToken, unstakingFee);
                }
            }
            if(user.amount > 0){
                user.stakedSince = currentBlock;
            }
            else {
                user.stakedSince = 0;
            }
            pool.lpToken.transfer(address(msg.sender), taxedAmount);
        }
        user.rewardDebt = user.amount * pool.accLotlPerShare / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw reward pool earnings, if there are any.
    function withdrawReward() public nonReentrant {
        uint128 share = rewardPoolShare[currentRewardIteration-1][msg.sender];
        require(share > 0, "withdraw: no reward share");
        uint128 busdPending = rewardInfo.amountBUSD * share / 1e12;
        uint128 lotlPending = rewardInfo.amountLOTL * share / 1e12;
        require (lotlPending <= rewardInfo.remainingLOTL && busdPending <= IERC20(busdAddr).balanceOf(address(this)), "withdraw: not enough funds in pool");
        rewardInfo.remainingLOTL = rewardInfo.remainingLOTL - lotlPending;
        IERC20(busdAddr).transfer(msg.sender, busdPending);
        lotl.transfer(msg.sender, lotlPending);
        share = 0;
        emit WithdrawReward(msg.sender, lotlPending, busdPending);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint8 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint128 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.transfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
    

    // One time set reward address.
    function setRewardAddress(address _rewardAddress) public{
        require(msg.sender == address(rewardPool), "rewards: wha?");
        rewardPool = IRewardPool(_rewardAddress);
        emit SetRewardAddress(msg.sender, _rewardAddress);
    }

    // One time set reward address.
    function setDevAddress(address _devAddress) public{
        require(msg.sender == address(devAddr), "rewards: wha?");
        devAddr = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    // Minting rate will be adjusted every 28800*(8/MintingRate) Blocks
    function updateMintingRate() public onlyOwner {
        massUpdatePools();
        if(lotlPerBlock == 0){
            lotlPerBlock = 2 * 1e18;
            return;
        }
        lotlPerBlock = lotlPerBlock / 2;
        emit UpdateMintingRate(msg.sender, lotlPerBlock);
    }

    // Calculates all rewardShares for all users that are registered as stakers. 
    function calculateRewardPool() external override {
        require(msg.sender == address(rewardPool), "rewards: wha?");

        uint8 length = uint8(poolInfo.length);
        uint32 totalUserLength = uint32(rewardInfo.poolUser.length);
        rewardInfo.amountBUSD = uint128(IERC20(busdAddr).balanceOf(address(this)));
        rewardInfo.amountLOTL = pendingRewardLotl + rewardInfo.remainingLOTL;
        rewardInfo.remainingLOTL = rewardInfo.amountLOTL;
        pendingRewardLotl = 0;
        uint32 currentBlock = uint32(block.number);
        uint128[] memory adjustedLiquidity = new uint128[](length);
        for(uint8 i=0; i < length; i++){
            PoolInfo memory pool = poolInfo[i];
            adjustedLiquidity[i] = 0;
            uint16 userLength = uint16(pool.poolUser.length);
                for(uint32 j=0; j < userLength; j++){
                    UserInfo memory user = userInfo[i][pool.poolUser[j]];
                    if(user.stakedSince > 0){
                        adjustedLiquidity[i] = adjustedLiquidity[i] + user.amount * (currentBlock - user.stakedSince);
                    }
                }
            }
        for(uint32 i=0; i < totalUserLength; i++){
            address rewardUser = rewardInfo.poolUser[i];
            uint128 adjustedAmount = 0;
            for(uint8 j=0; j < length; j++){
                UserInfo memory user = userInfo[j][rewardUser];
                if(user.amount > 0){
                    wasAmount = true;
                }
                if(user.stakedSince > 0){
                    wasStakedSince = true;
                    PoolInfo memory pool = poolInfo[j];
                    adjustedAmount = adjustedAmount + user.amount * 1e12 * (currentBlock - user.stakedSince) / adjustedLiquidity[j] * pool.allocPoint / totalAllocPoint;
                }
            }
 
            rewardPoolShare[currentRewardIteration][rewardUser] = adjustedAmount;
        }
        currentRewardIteration++;
        rewardPool.resetBurnCycle();
    }
}
