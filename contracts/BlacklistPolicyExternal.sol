// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../interfaces/IBlacklistPolicy.sol";
import 'OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/access/AccessControlEnumerable.sol';

interface SanctionsList {
    function isSanctioned(address addr) external view returns (bool);
}

contract BlacklistPolicyExternal is IBlacklistPolicy, AccessControlEnumerable {

    bytes32 public constant MAIN_ADMIN = keccak256('MAIN_ADMIN');
    bytes32 public constant CHILD_ADMIN = keccak256('CHILD_ADMIN');

    constructor()
    {
        _grantRole(MAIN_ADMIN, msg.sender);
        _setRoleAdmin(MAIN_ADMIN, MAIN_ADMIN);
        _grantRole(CHILD_ADMIN, msg.sender);
        _setRoleAdmin(CHILD_ADMIN, MAIN_ADMIN);
    }

    SanctionsList public oracle;

    function updateBlacklistOracle(address newOracleAddress)
    external onlyRole(CHILD_ADMIN)
    returns (bool)
    {
        require(newOracleAddress != address(0), "Invalid address");
        oracle = SanctionsList(newOracleAddress);
        return true;
    }

    function _policy(address from, address to, uint256 amount)
    internal view
    returns (bool)
    {
        if (oracle.isSanctioned(to) || oracle.isSanctioned(from)) {
                return false;
        }
        return true;
    }

    function transferPolicy(address from, address to, uint256 amount)
    external view override
    returns (bool)
    {
        return _policy(from, to, amount);
    }

    function depositPolicy(uint256 assets, uint256 shares, address receiver, address sender)
    external view override
    returns (bool)
    {
        return _policy(receiver, sender, assets);
    }

    function withdrawPolicy(uint256 assets, uint256 shares, address receiver, address sender)
    external view override
    returns (bool)
    {
        return _policy(receiver, sender, assets);
    }
}
