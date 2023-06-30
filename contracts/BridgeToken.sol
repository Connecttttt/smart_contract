// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgeToken is ERC20 {
    constructor() ERC20("Bridge Token ", "BRG") {}

    function mintFree(address _user, uint256 _amount) public {
        _mint(_user, _amount);
    }
}
