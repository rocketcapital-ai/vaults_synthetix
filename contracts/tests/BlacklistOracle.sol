// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;


contract BlacklistOracle {

    constructor() {}
    mapping (address => bool) public isBlacklisted;

    function updateAddress(address userAddress, bool status)
    external
    {
        isBlacklisted[userAddress] = status;
    }
}
