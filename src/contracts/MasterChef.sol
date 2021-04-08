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
        uint256 amount;                 // How many LP tokens the user has provided.
        uint256 rewardDebt;             // Reward debt. See explanation below.
        bool    hasStaked;              // Checks if user had already staked in pool
        uint256 stakedSince;            // Weighted blocknumber since last stake.  
        uint256 rewardPoolShare;        // Share of reward pool.

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
        //  1. First of, we reserve 30% of all minted LOTL to our reward pool. ('lotlRewardPool')
        //  2. We send 90% of all taxes paid to our RewardPool contract.
        //  3. All fees will be swapped to BUSD and sent back to the MasterChef contract.
        //  4. Then we use calculateRewardPool to calculate all rewards per share for each user and sum them up for each user across all pools he staked in.
        //  5. rewardPerShare = 1 * pool.allocPoint * timeReward * user.amount / totalAllocPoint / lpSupply
        //  6. Then to get your actual reward you need to withdraw your rewards before the next reward pool is distributed or else they will be burned.
        //  7. Rewards are paid out in the function 'withdrawRewards' and are finally calculated as follows.
        //  8. reward = totalRewardPool * user.rewardPoolShare / totalTimeAlloc 
     


                
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;             // Address of LP token contract.
        uint8 allocPoint;           // How many allocation points assigned to this pool. LOTLs to distribute per block.
        uint256 lastRewardBlock;     // Last block number that LOTLs distribution occurs.
        uint256 accLotlPerShare;     // Accumulated LOTLs per share, times 1e12. See below.
        uint16 depositFeeBP;        // Deposit fee in basis points.
        uint64 totalTimeAlloc;      // Total amount of time allocation points.
        address []poolUser;         // Addresses of all stakes in pool.
    }

    // Info for the reward pool.
    // All rewards that haven't been claimed until the next reward distribution will be nulled and added to the next distribution. 
    struct Rewards {
        uint64 totalTimeAlloc;      // Total time factor for all stakes.
        uint256 amountBUSD;         // BUSD to distribute among all stakers.
        uint256 amountLOTL;         // LOTL to distribute among all stakers.
        uint256 remainingLOTL;      // Remainder of LOTL.
        address []poolUser;         // Addresses of all stakes in pool.
    }

    // Lotl to allocate to reward pool.
    uint256 pendingRewardLotl; 
    
    // Info of reward pool.
    Rewards public rewardInfo;

    // The LOTL TOKEN!
    LotlToken public lotl;

    // Dev address.
    address public devaddr;

    // RewardPool address.
    IRewardPool public rewardPool;

    

    // LOTL tokens created per block.
    uint256 public lotlPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    // Mapping 0 is reserved for the rewardPool.
    mapping(uint8 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint64 public totalAllocPoint = 0;


    event Deposit(address indexed user, uint8 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint8 indexed pid, uint256 amount);
    event WithdrawReward(address indexed user, uint256 amountLotl, uint256 amountBUSD);
    event EmergencyWithdraw(address indexed user, uint8 indexed pid, uint256 amount);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event SetRewardAddress(address indexed user, address indexed newAddress);
    event UpdateMintingRate(address indexed user, uint256 lotlPerBlock);
    
    

    constructor(
        LotlToken _lotl
    ) public {
        lotl = _lotl;
        devaddr = msg.sender;
        rewardPool = IRewardPool(msg.sender);
    }

    function poolLength() external view returns (uint8) {
        return uint8(poolInfo.length);
    }

    // Used to determine wether a pool has already been added.
    mapping(IERC20 => bool) public poolExistence;

    // Modifier to allow only new pools being added.
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // TODO TEST IF ADDING TOKENS AS POOL WORKS 
    // Add a new lp to the pool. Can only be called by the owner.

    function add(uint8 _allocPoint, IERC20 _lpToken, IERC20 _tokenA, IERC20 _tokenB, uint16 _depositFeeBP, bool _withUpdate, bool _isLPPool) public onlyOwner nonDuplicated(_lpToken) {
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
        poolToAdd.lastRewardBlock = block.number;
        poolToAdd.depositFeeBP =  _depositFeeBP;
        poolInfo.push(poolToAdd);
    }

    // View function to see pending LOTLs on frontend.
    function pendingLotl(uint8 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid + 1][_user];
        uint256 accLotlPerShare = pool.accLotlPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 lotlReward =  (block.number - pool.lastRewardBlock) * lotlPerBlock * pool.allocPoint / totalAllocPoint;
            accLotlPerShare = accLotlPerShare + lotlReward * 1e12 / lpSupply;
        }
        return accLotlPerShare * user.amount / 1e12 - user.rewardDebt;
    }

    // View function to see pending rewards on frontend.
    // TODO TEST
    function pendingRewards(address _user) external view returns (uint256 _lotl, uint256 _busd) {
        UserInfo storage user = userInfo[0][_user];
        require(user.rewardPoolShare > 0, "withdraw: not good");
        if(user.rewardPoolShare > 0){
            uint256 busdPending = rewardInfo.amountBUSD * user.rewardPoolShare / rewardInfo.totalTimeAlloc / 1e12;
            uint256 lotlPending = rewardInfo.amountLOTL * user.rewardPoolShare / rewardInfo.totalTimeAlloc / 1e12;
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
    // TEST IF DIVIDES WITHOUT REST
    function calculateTimeRewards (uint256 _stakedSince) private returns (uint256)  {
        /*
        uint256 timeFactor = (block.number - _stakedSince) / 14400;
        if(timeFactor == 0){
            return 1;
        }
        else{
            return timeFactor;
        }
        */
        //testing
        return block.number - _stakedSince;
    } 

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint8 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        if(lotlPerBlock == 0){
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 lotlReward = (block.number - pool.lastRewardBlock) * lotlPerBlock * pool.allocPoint / totalAllocPoint;
        //TODO test minting 
        lotl.mint(devaddr, lotlReward / 10);
        pendingRewardLotl = pendingRewardLotl + lotlReward / 10 * 3;
        lotl.mint(address(this), lotlReward - lotlReward / 10);
        lotlReward = lotlReward - (lotlReward / 10 * 4);
        pool.accLotlPerShare = pool.accLotlPerShare + lotlReward * 1e12 / lpSupply;
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for LOTL allocation.
    function deposit(uint8 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid+uint8(1)][msg.sender];
        UserInfo storage rewardUser = userInfo[0][msg.sender];
        updatePool(_pid);

        // Save last block number as staking timestamp
        if (user.stakedSince == 0 && _amount > 0)
        {
             //TODO TEST IF FIRST STACKE SETS STAKED SINCE
            user.stakedSince = block.number;
        }
        
        if (user.amount > 0) 
        {
            uint256 pending = user.amount * pool.accLotlPerShare / 1e12 - user.rewardDebt;
            if (pending > 0) 
            {
                safeLotlTransfer(msg.sender, pending);
            }
        } 
        if (_amount > 0) 
        {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 taxedAmount = _amount * (1e4 - pool.depositFeeBP) / 1e4;

            // Holding factor scaling
            if(user.amount > 0)
            {
                user.stakedSince = user.stakedSince + (block.number - user.stakedSince) * taxedAmount / (user.amount + taxedAmount);
            }

            //TODO TEST IF PUSHING WORKS
            if(!user.hasStaked)
            {
                pool.poolUser.push(msg.sender);
                user.hasStaked = true;

            }
            if(!rewardUser.hasStaked)
            {
                rewardInfo.poolUser.push(msg.sender);
                rewardUser.hasStaked = true;
            }
            if (pool.depositFeeBP > 0) 
            {
                uint256 depositFee = _amount - taxedAmount;
                pool.lpToken.safeTransfer(devaddr, depositFee / 10);
                pool.lpToken.safeTransfer(address(rewardPool), depositFee - depositFee / 10);
            } 

            user.amount = user.amount + taxedAmount;
            
        }
        user.rewardDebt = user.amount * pool.accLotlPerShare / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint8 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid + 1][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount * pool.accLotlPerShare / 1e12 - user.rewardDebt;
        if (pending > 0) 
        {
            safeLotlTransfer(msg.sender, pending);
        }
        if (_amount > 0) 
        {
            user.amount = user.amount - _amount;

            //TODO TEST IF UNSTAKING RESETS stakedSince
            if(user.amount > 0)
            {
                user.stakedSince = block.number;
            }
            else 
            {
                user.stakedSince = 0;
            }
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount * pool.accLotlPerShare / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw reward pool earnings, if there are any.
    function withdrawReward() public nonReentrant {
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.rewardPoolShare > 0, "withdraw: not good");
        uint256 busdPending = rewardInfo.amountBUSD * user.rewardPoolShare / rewardInfo.totalTimeAlloc / 1e12;
        uint256 lotlPending = rewardInfo.amountLOTL * user.rewardPoolShare / rewardInfo.totalTimeAlloc / 1e12;
        rewardInfo.remainingLOTL = rewardInfo.remainingLOTL - lotlPending;
        safeLotlTransfer(msg.sender, lotlPending);
        safeBusdTransfer(msg.sender, busdPending);
        user.rewardPoolShare = 0;
        emit WithdrawReward(msg.sender, lotlPending, busdPending);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint8 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid + 1][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe LOTL transfer function, just in case if rounding error causes pool to not have enough LOTLs.
    function safeLotlTransfer(address _to, uint256 _amount) internal {
        uint256 lotlBal = lotl.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > lotlBal) {
            transferSuccess = lotl.transfer(_to, lotlBal);
        } else {
            transferSuccess = lotl.transfer(_to, _amount);
        }
        require(transferSuccess, "safeLotlTransfer: transfer failed");
    }


    // Safe BUSD transfer function, just in case if rounding error causes pool to not have enough BUSDs.
    function safeBusdTransfer(address _to, uint256 _amount) internal {
        uint256 busdBal = IERC20(busdAddr).balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > busdBal) {
            transferSuccess = IERC20(busdAddr).transfer(_to, busdBal);
        } else {
            transferSuccess = IERC20(busdAddr).transfer(_to, _amount);
        }
        require(transferSuccess, "safeBusdTransfer: transfer failed");
    }


    // Update dev address by the previous dev.
    function setDevAddress(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

     // One time set reward address.
    function setRewardAddress(address _rewardAddress) public{
        require(msg.sender == address(rewardPool), "rewards: wha?");
        rewardPool = IRewardPool(_rewardAddress);
        emit SetRewardAddress(msg.sender, _rewardAddress);
    }

   
    // Minting rate will be adjusted every 28800*(8/MintingRate) Blocks
    function updateMintingRate() public onlyOwner {
        massUpdatePools();
        lotlPerBlock = lotlPerBlock / 2;
        emit UpdateMintingRate(msg.sender, lotlPerBlock);
    }


    // Start the block rewards.
    function startMinting() public onlyOwner {
        if(lotlPerBlock == 0)
        {
        massUpdatePools();
        lotlPerBlock = 4 * 1e18;
        }
    }
    

    // Calculates all rewardShares for all users that are registered as stakers. 
    /*  TODO TEST
        1. Burning works
        2. rewardPoolShare = 0 for loop
        3. totalTimeALlocation rewardPool
        4. rewardPoolShare formula correct
        5. lotl and busd reward pool correct
    */

    function calculateRewardPool() external override {
        //require(msg.sender == rewardAddress, "rewards: wha?");
        uint8 length = uint8(poolInfo.length);
        uint32 rewardUserlength = uint32(rewardInfo.poolUser.length);
        rewardInfo.amountBUSD =IERC20(busdAddr).balanceOf(address(this));
        rewardInfo.amountLOTL = pendingRewardLotl + rewardInfo.remainingLOTL;
        rewardInfo.remainingLOTL = rewardInfo.amountLOTL;
        pendingRewardLotl = 0;
        rewardInfo.totalTimeAlloc = 0;
        for(uint32 i; i< rewardUserlength; i++){
            UserInfo storage user = userInfo[0][rewardInfo.poolUser[i]];
            user.rewardPoolShare = 0;
        }

        for (uint8 i=0; i < length; i++){
            PoolInfo storage pool = poolInfo[i];
            uint256 lpSupply = pool.lpToken.balanceOf(address(this));
            uint32 userLength = uint32(pool.poolUser.length);
            poolInfo[i].totalTimeAlloc = 0;
            for(uint32 j; j< userLength; j++){
                UserInfo storage user = userInfo[i+1][pool.poolUser[j]];
                if(user.stakedSince > 0){
                    UserInfo storage rewardUser = userInfo[0][poolInfo[i].poolUser[j]];
                    uint64 timeReward = uint64(calculateTimeRewards(user.stakedSince));
                    pool.totalTimeAlloc = pool.totalTimeAlloc + timeReward;
                    rewardUser.rewardPoolShare = rewardUser.rewardPoolShare + user.amount * 1e12 / totalAllocPoint * pool.allocPoint / lpSupply * timeReward;

                }
            }
            rewardInfo.totalTimeAlloc = rewardInfo.totalTimeAlloc + pool.totalTimeAlloc;
        }
    }

    function currentHoldingFactor(uint8 _pid, address _user) public view returns(uint256 holdFactor){
        UserInfo storage user = userInfo[_pid][_user];
        if(user.stakedSince > 0)
        {
            return block.number - user.stakedSince;
        }
        else return 0;

    }


}
