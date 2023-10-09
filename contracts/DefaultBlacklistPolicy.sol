// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../interfaces/IBlacklistPolicy.sol";

contract DefaultBlacklistPolicy is IBlacklistPolicy {

    constructor() {}

    function transferPolicy(address from, address to, uint256 amount)
    external view override
    returns (bool)
    {
        return true;
    }

    function depositPolicy(uint256 assets, uint256 shares, address receiver, address sender)
    external view override
    returns (bool)
    {
        return true;
    }

    function withdrawPolicy(uint256 assets, uint256 shares, address receiver, address sender)
    external view override
    returns (bool)
    {
        return true;
    }
}
