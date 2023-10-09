// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../../interfaces/IBlacklistPolicy.sol";
import 'OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/access/AccessControlEnumerable.sol';
import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/token/ERC20/ERC20.sol";

contract BlacklistPolicyWhitelist is IBlacklistPolicy, AccessControlEnumerable {

    mapping (address => bool) public isBlacklisted;
    mapping (address => bool) public isWhitelisted;

    bytes32 public constant MAIN_ADMIN = keccak256('MAIN_ADMIN');
    bytes32 public constant CHILD_ADMIN = keccak256('CHILD_ADMIN');

    constructor() {
        _grantRole(MAIN_ADMIN, msg.sender);
        _setRoleAdmin(MAIN_ADMIN, MAIN_ADMIN);
        _grantRole(CHILD_ADMIN, msg.sender);
        _setRoleAdmin(CHILD_ADMIN, MAIN_ADMIN);
    }

    function updateBlacklist(address acct, bool toBlacklist)
    external onlyRole(CHILD_ADMIN)
    returns (bool)
    {
        isBlacklisted[acct] = toBlacklist;
        return true;
    }

    function updateWhitelist(address acct, bool toWhitelist)
    external onlyRole(CHILD_ADMIN)
    returns (bool)
    {
        isWhitelisted[acct] = toWhitelist;
        return true;
    }

    function _policy(address from, address to)
    internal view
    returns (bool)
    {
        return !(isBlacklisted[to] || isBlacklisted[from]);
    }

    function transferPolicy(address from, address to, uint256 amount)
    external view override
    returns (bool)
    {
        return (
        isWhitelisted[from] || isWhitelisted[to]
        || (from == address(0)) // for minting
        || (to == address(0)) // for burning
        );
    }

    function depositPolicy(uint256 assets, uint256 shares,address receiver, address sender)
    external view override
    returns (bool)
    {
        return _policy(receiver, sender);
    }

    function withdrawPolicy(uint256 assets, uint256 shares,address receiver, address sender)
    external view override
    returns (bool)
    {
        return _policy(receiver, sender);
    }
}
