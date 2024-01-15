// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract W3MToken is ERC20 {
    constructor( ) ERC20("W3MToken", "W3M") {
        _mint(msg.sender, 500000000 * 10 ** decimals());
    }
    
}