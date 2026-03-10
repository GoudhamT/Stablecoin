//SPDX-License-Identifier:MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title Decentralized Stablecoin
 * @author Goudham T
 * Collateral : Exogeneous
 * Minting : Algorthmic
 * Relative Stability: pegged to USD
 * This is contract ment to be governred by DSCEngine, This is ERC20 implementation of our stablecoin
 */
contract DecentrlizedStableCoin is ERC20Burnable, Ownable {
    /*Errors */
    error DecentrlizedStableCoin__AmountCannotBeZero();
    error DecentrlizedStableCoin__AmountExceedsBalance();
    error DecentrlizedStableCoin__AddressCannotBeNull();

    constructor() ERC20("Decentralized Stablecoin", "GDSC") Ownable(msg.sender) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentrlizedStableCoin__AmountCannotBeZero();
        }
        if (balance <= _amount) {
            revert DecentrlizedStableCoin__AmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentrlizedStableCoin__AddressCannotBeNull();
        }
        if (_amount <= 0) {
            revert DecentrlizedStableCoin__AmountCannotBeZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
