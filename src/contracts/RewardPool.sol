pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libs/Constants.sol";
import "./libs/IPancakeRouter02.sol";
import "./libs/IMasterChef.sol";
import "./libs/IRewardPool.sol";
// CHANGE FOR BSC
//import "./libs/SafeBEP20.sol";
//import "./libs/IBEP20.sol";
/*
Note: This contract is ownable, therefor the owner wields a good portion of power.
The owner will be able:
-   initiate the reward pool 
-   transfer BUSD to masterChef contract
-   remove liquidity to token pairs
-   swap tokens to BUSD
-   swap 20% of BUSD to LOTL
-   burn all present LOTL
The BUSD address is a set constant derived from ./libs/Constants.sol and not changeable.
Thus the owner has only the power to withhold all the funds in this contract
but can only transfer them to the masterChef contract in form of BUSD.
This contract uses the UniSwapRouter interfaces to: 
    removeAllLiquidity of LP tokens
    swap all tokens to BUSD
    swap 20% to Lotl
    burn that lotl
    transfer the remaining BUSD to MasterChef
    initiate reward distribution
*/
contract RewardPool is Ownable, Constants, IRewardPool {
    using SafeERC20 for IERC20;
    IMasterChef public chef;
    address public lotlToken;
    // Tokens associated with the LP pair. 
    struct LpTokenPair {
    	IERC20 tokenA;
        IERC20 tokenB;
    }
    // All different LP tokens registered.
    IERC20[] public lptoken;
	// All different tokens registered.
	IERC20[] public tokens; 
    // Swapping paths.
    mapping(address => mapping(address => address[])) paths;
	// Maps the LP pair to the tokens 
	mapping (IERC20 => LpTokenPair) public lpPairs;
	// Used to determine wether a pool has already been added.
    mapping(IERC20 => bool) public poolExistence;
    // Used to determine wether a token has already been added.
    mapping(IERC20 => bool) public tokenExistence;
    // Limits the Owner to a maximum of one burn per reward pool cycle.
    bool public hasSwappedToLotlThisCycle;
    // Modifier to allow only new pools being added.
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }
    event BurnLotl(address indexed lotl, uint256 amount);
    event TransferAllBUSD(address indexed user, uint256 amount);
    event DistributeRewardPool(address indexed);
    event CalculateRewards(address indexed);
  	constructor(address _chef, address _lotl) public {
  		chef = IMasterChef(_chef);
        lotlToken = _lotl;
        hasSwappedToLotlThisCycle = false;
  		 // Sell Tokens Paths BSC
         /*
		paths[wbnbAddr][busdAddr] = [wbnbAddr, busdAddr];
		paths[usdtAddr][busdAddr] = [usdtAddr, busdAddr];

		paths[btcbAddr][busdAddr] = [btcbAddr, wbnbAddr, busdAddr];
		paths[wethAddr][busdAddr] = [wethAddr, wbnbAddr, busdAddr];
		paths[daiAddr][busdAddr] = [daiAddr, busdAddr];
		paths[usdcAddr][busdAddr] = [usdcAddr, busdAddr];
		paths[dotAddr][busdAddr] = [dotAddr, wbnbAddr, busdAddr];
		paths[cakeAddr][busdAddr] = [cakeAddr, wbnbAddr, busdAddr];
		paths[worldAddr][busdAddr] = [worldAddr, wbnbAddr, busdAddr];
		paths[gnyAddr][busdAddr] = [gnyAddr, wbnbAddr, busdAddr];
		paths[vaiAddr][busdAddr] = [vaiAddr, ustAddr, wbnbAddr, busdAddr];
        */
        // Ropsten paths
        paths[wbnbAddr][busdAddr] = [wbnbAddr, busdAddr];
        paths[lotlToken][busdAddr] = [lotlToken, busdAddr];
        paths[busdAddr][lotlToken] = [busdAddr, lotlToken];
  		}
  	// Function to add router paths, needed if new LP pairs with new tokens are added.
  	function setRouterPath(address inputToken, address outputToken, address[] calldata _path, bool overwrite) external onlyOwner {
        address[] storage path = paths[inputToken][outputToken];
        uint256 length = _path.length;
        if (!overwrite) {
            require(length == 0, "setRouterPath: ALREADY EXIST");
        }
        for (uint8 i = 0; i < length; i++) {
            path.push(_path[i]);
        }
    }
    // Uses input token and output token to determine best swapping path.
    function getRouterPath(address inputToken, address outputToken) private view returns (address[] storage){
        address[] storage path = paths[inputToken][outputToken];
        require(path.length > 0, "getRouterPath: MISSING PATH");
        return path;
    }
    // Returns current time + 60 second.
    function getTxDeadline() private view returns (uint256){
        return block.timestamp + 60;
    }
    // Swaps BUSD to LOTL without concern about minimum/slippage.
    function swapToLotl() public onlyOwner{
        if(hasSwappedToLotlThisCycle){
            return;
        }
        IERC20(busdAddr).approve(routerAddr, IERC20(busdAddr).balanceOf(address(this))/5);
        IPancakeRouter02(routerAddr).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            IERC20(busdAddr).balanceOf(address(this))/5,
            0,
            getRouterPath(busdAddr, lotlToken),
            address(this),
            getTxDeadline()
        );
        hasSwappedToLotlThisCycle = true;
    }
    // Transfers all BUSD to MasterChef
    function transferAllBUSD () public onlyOwner {
        IERC20(busdAddr).transfer(address(chef), IERC20(busdAddr).balanceOf(address(this)));
        emit TransferAllBUSD(msg.sender, IERC20(busdAddr).balanceOf(address(this)));
    }    

    // Initiates the reward calculation in the MasterChefContract
    function calculateRewards() public onlyOwner{
        chef.calculateRewardPool();
        emit CalculateRewards(msg.sender);
    }

    // Burns LOTL.
    function burnLotl () public onlyOwner {
        IERC20(lotlToken).transfer(burnAddr, IERC20(lotlToken).balanceOf(address(this)));
        emit BurnLotl(msg.sender, IERC20(lotlToken).balanceOf(address(this)));
    }
    // Swaps token to BUSD supporting fees on token.
    function swapToBusd(IERC20 _inputToken, uint256 _amount) private{
        if(_inputToken == IERC20 (busdAddr)){
            return;
        }
        _inputToken.approve(routerAddr, _amount);
        IPancakeRouter02(routerAddr).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount,
            0,
            getRouterPath(address(_inputToken), busdAddr),
            address(this),
            getTxDeadline()
        );
    } 
    // Breaks up liquidity pools into tokens and swaps tokens to BUSD.
    function removeLiquidityExternal (IERC20 _lpToken, uint256 _amount) public override{
        require(msg.sender == address(chef) ,"chef: u no master");
        _lpToken.approve(routerAddr, _lpToken.balanceOf(address(this)));
        IERC20 _tokenA = lpPairs[_lpToken].tokenA;
        IERC20 _tokenB = lpPairs[_lpToken].tokenB;
        uint256 amountA;
        uint256 amountB;
        (amountA, amountB) = IPancakeRouter02(routerAddr).removeLiquidity(
            address(_tokenA),
            address(_tokenB),
            _amount,
            0,
            0,
            address(this),
            getTxDeadline()
        );
        if(_tokenA != IERC20(busdAddr)){
            swapToBusd(_tokenA, amountA);
        }
        if(_tokenB != IERC20(busdAddr)){
            swapToBusd(_tokenB, amountB);
        } 
    }
    // Calls private function swapToBusd.
    function swapToBusdExternal(IERC20 _token,  uint256 _amount) public override{
        require(msg.sender == address(chef) ,"chef: u no master");
        swapToBusd(_token, _amount);
    }
    // Resets burn cycle, called by masterchef after reward distribution
    function resetBurnCycle() public override{
        require(msg.sender == address(chef) ,"chef: u no master");
        hasSwappedToLotlThisCycle = false;
    }
   	// Add new LP tokens and tokens to the existing storage, can only be called via MasterChef contract.
    function addLpToken(IERC20 _lpToken, IERC20 _tokenA, IERC20 _tokenB, bool isLPToken) public override nonDuplicated(_lpToken){
        require(msg.sender == address(chef) ,"chef: u no master");
        if(isLPToken)
        {
    		lptoken.push(_lpToken);
    		poolExistence[_lpToken] = true;
    		LpTokenPair storage lp = lpPairs[_lpToken];
    		lp.tokenA = _tokenA;
    		lp.tokenB = _tokenB;
    		if(!tokenExistence[_tokenB])
            {
    			tokens.push(_tokenB);
    			tokenExistence[_tokenB] = true;
    		}
    		if(!tokenExistence[_tokenA])
            {
    			tokens.push(_tokenA);
    			tokenExistence[_tokenA] = true;
    		}
        }
        else 
        {
            if(!tokenExistence[_lpToken])
            {
            tokens.push(_lpToken);
            tokenExistence[_lpToken] = true;
            }

    	}
    }
}

