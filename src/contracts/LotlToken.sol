pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";



//CHANGE FOR BSC
//import "./libs/BEP20.sol";




// LotlToken
contract LotlToken is ERC20('Axolotl', 'LOTL'), Ownable {

    // Initial minting tokens.
    // 50000 sold in ICO.
    // 30000 used for initial liquidity pools.
    // Owner will be transferred to MasterChef contract and thus will be governed by that contract.
    // We do not see the need for a community governed Token. 

    /// @notice Creates `_amount` token to `_to`. Must only be called by the master (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

}