// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../interfaces/IShareTaxPolicy.sol";
import 'OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/access/AccessControlEnumerable.sol';

contract ShareTaxPolicyVanilla is IShareTaxPolicy, AccessControlEnumerable {

    mapping (address => bool) public vip; // vip: no taxes when sending.
    mapping (address => bool) public exempt; // exempt: no taxes when sending or receiving.
    address public federalTaxCollector;
    address public stateTaxCollector;
    uint256 public federalTaxPercentage;
    uint256 public stateTaxPercentage;
    uint256 public taxDecimals;
    uint256 public taxUnits;
    
    bytes32 public constant MAIN_ADMIN = keccak256('MAIN_ADMIN');
    bytes32 public constant CHILD_ADMIN = keccak256('CHILD_ADMIN');

    constructor(address federalTaxCollector_,
                address stateTaxCollector_,
                uint256 federalTaxPercentage_,
                uint256 stateTaxPercentage_,
                uint256 taxDecimals_
    ) {
        _grantRole(MAIN_ADMIN, msg.sender);
        _setRoleAdmin(MAIN_ADMIN, MAIN_ADMIN);
        _grantRole(CHILD_ADMIN, msg.sender);
        _setRoleAdmin(CHILD_ADMIN, MAIN_ADMIN);

        federalTaxCollector = federalTaxCollector_;
        stateTaxCollector = stateTaxCollector_;
        federalTaxPercentage = federalTaxPercentage_;
        stateTaxPercentage = stateTaxPercentage_;
        taxDecimals = taxDecimals_;
        taxUnits = 10 ** taxDecimals_;
    }

    function updateVip(address newVipAddress, bool toAdd)
    external onlyRole(CHILD_ADMIN)
    returns (bool)
    {
        vip[newVipAddress] = toAdd;
        return true;
    }

    function updateExempt(address newExemptAddress, bool toAdd)
    external onlyRole(CHILD_ADMIN)
    returns (bool)
    {
        exempt[newExemptAddress] = toAdd;
        return true;
    }

    function updateFederalTaxPercentage(uint256 newPercentage)
    external onlyRole(CHILD_ADMIN)
    returns (bool)
    {
        federalTaxPercentage = newPercentage;
        return true;
    }

    function updateStateTaxPercentage(uint256 newPercentage)
    external onlyRole(CHILD_ADMIN)
    returns (bool)
    {
        stateTaxPercentage = newPercentage;
        return true;
    }

    function shareTaxActions(address from, address to, uint256 amount)
    external view override
    returns (ShareTaxTransfers[3] memory shareTaxTransfers)
    {
        if (!(exempt[from] || exempt[to] || vip[from])) {
            shareTaxTransfers[0] = ShareTaxTransfers({
                                    payer: from,
                                    collector: federalTaxCollector,
                                    amount: computeFederalTax(amount)
            });
            shareTaxTransfers[1] = ShareTaxTransfers({
                                    payer: from,
                                    collector: stateTaxCollector,
                                    amount: computeStateTax(amount)
            });
        }
    }

    function computeFederalTax(uint256 amount)
    public view
    returns (uint256)
    {
        return federalTaxPercentage * amount / taxUnits;
    }

    function computeStateTax(uint256 amount)
    public view
    returns (uint256)
    {
        return stateTaxPercentage * amount / taxUnits;
    }
}
