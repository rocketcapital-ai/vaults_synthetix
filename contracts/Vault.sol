// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./ShareToken.sol";

contract Vault is ShareToken {

    address public om;
    bool public omInitialized;


    constructor(string memory name_,
        string memory symbol_,
        address blacklistPolicy_)
    ShareToken(name_, symbol_, blacklistPolicy_, msg.sender)
    {}

    function initializeOm(address om_)
    external
    onlyRole(MAIN_ADMIN)
    {
        require(!omInitialized, "OM already initialized");
        require(om_ != address(0), "Invalid address");
        om = om_;
        omInitialized = true;
    }

    function shareMint(address to, uint256 amount)
    external
    {
        require(msg.sender == om, "Invalid sender");
        _shareMint(to, amount);
    }

    function burnShares(uint256 amtToBurn)
    external
    {
        require(msg.sender == om, "Invalid sender");
        _burnShares(om, amtToBurn);
    }



}
