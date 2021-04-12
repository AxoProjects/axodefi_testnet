// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "./libs/BEP20.sol";

// WBNB
contract WbnbToken is BEP20('WBNB', 'WBNB') {

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}