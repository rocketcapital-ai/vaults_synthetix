// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IShareTaxPolicy{

    struct ShareTaxTransfers {
        address payer;
        address collector;
        uint256 amount;
    }

    /*
    @dev: Abstraction for external share tax policy contract.
    @dev: The only function here, shareTaxActions, returns an array of taxes to be paid
    @dev: along with the payer and collector addresses.
    */
    function shareTaxActions(address from, address to, uint256 amount)
    external view
    returns (ShareTaxTransfers[3] memory);
}
