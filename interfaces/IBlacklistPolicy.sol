// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IBlacklistPolicy{

    /*
    @dev: Abstraction for external blacklist policy contract. Every function should return a boolean status
    @dev: that indicates if a transaction should be allowed by the blacklist policy. The boolean value should be false
    @dev: if the transaction is not allowed.
    */

    function transferPolicy(address from, address to, uint256 amount)
    external view returns (bool);

    function depositPolicy(uint256 assets, uint256 shares, address receiver, address sender)
    external view returns (bool);

    function withdrawPolicy(uint256 assets, uint256 shares, address receiver, address sender)
    external view returns (bool);
}
