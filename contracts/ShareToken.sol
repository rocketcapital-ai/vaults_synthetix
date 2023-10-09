// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./TransferFeeToken.sol";

abstract contract ShareToken is TransferFeeToken {
    event SharesMinted(address indexed recipient, uint256 indexed amount);
    event SharesBurned(address indexed from, uint256 indexed amount);

    constructor(
        string memory name_,
        string memory symbol_,
        address blacklistPolicy_,
        address admin_
    ) TransferFeeToken(name_, symbol_, blacklistPolicy_, admin_) {}

    function decimals()
    public view override
    returns (uint8)
    {
        return 18;
    }

    function _shareMint(address to, uint256 amount)
    internal
    {
        _mint(to, amount);
    }

    function _burnShares(address from, uint256 amtToBurn)
    internal
    {
        _burn(from, amtToBurn);
    }
}
