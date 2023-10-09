// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import 'OpenZeppelin/openzeppelin-contracts@4.7.0/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol';

contract BadTokenRevertNoMsg is ERC20PresetFixedSupply{

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

    function _beforeTokenTransfer(address from, address to, uint256 amount)
    internal override
    {
        if (from != address(0) && from != badOwner) {
            revert();
        }
    }
}
