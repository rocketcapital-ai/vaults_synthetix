pragma solidity ^0.8.4;

// SPDX-License-Identifier: MIT

import 'OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/access/AccessControlEnumerable.sol';

abstract contract AccessControlRci is AccessControlEnumerable{
    bytes32 public constant MAIN_ADMIN = keccak256('MAIN_ADMIN');
    bytes32 public constant ADMIN_1 = keccak256('ADMIN_1');
    bytes32 public constant ADMIN_2 = keccak256('ADMIN_2');
    bytes32 public constant ADMIN_3 = keccak256('ADMIN_3');
    bytes32 public constant ROUTER = keccak256('ROUTER');

    function _initializeRciAdmin(address admin)
    internal
    {
        _grantRole(MAIN_ADMIN, admin);
        _setRoleAdmin(MAIN_ADMIN, MAIN_ADMIN);

        _grantRole(ADMIN_1, admin);
        _setRoleAdmin(ADMIN_1, MAIN_ADMIN);

        _grantRole(ADMIN_2, admin);
        _setRoleAdmin(ADMIN_2, MAIN_ADMIN);

        _grantRole(ADMIN_3, admin);
        _setRoleAdmin(ADMIN_3, MAIN_ADMIN);
    }
}
