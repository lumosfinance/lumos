// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


import "./common/ERC20.sol";
import "./common/Ownable.sol";


// LumosToken
contract LumosToken is ERC20("Lumos", "LMS"), Ownable {
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}