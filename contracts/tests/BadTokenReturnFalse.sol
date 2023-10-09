// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import 'OpenZeppelin/openzeppelin-contracts@4.7.0/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol';

contract BadTokenReturnFalse is ERC20PresetFixedSupply{

    address badOwner;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address owner
    ) ERC20PresetFixedSupply(name, symbol, initialSupply, owner)
    {
        badOwner = owner;
    }

    function decimals()
    public view override
    returns (uint8)
    {
        return 6;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = msg.sender;
        uint256 currentAllowance = allowance(from, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                return false;
            }
        }

        if (from == address(0)) {
            return false;
        }
        if (to == address(0)) {
            return false;
        }

        uint256 fromBalance = balanceOf(from);
        if (fromBalance < amount) {
            return false;
        }

        return true;
    }
}
