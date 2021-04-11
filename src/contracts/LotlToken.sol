pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
//CHANGE FOR BSC
//import "./libs/BEP20.sol";
// LotlToken
contract LotlToken is ERC20('Axolotl', 'LOTL'), Ownable {
    /// @notice Creates `_amount` token to `_to`. Must only be called by the master (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

}