// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

//import "./IBEP20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardPool{
    function addLpToken(IERC20 _lpToken, IERC20 _tokenA, IERC20 _tokenB, bool _isLPToken) external;
    function processFees() external;
    function setRouterPath(address inputToken, address outputToken, address[] calldata _path, bool overwrite) external;
}