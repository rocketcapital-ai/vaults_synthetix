// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./../interfaces/IBlacklistPolicy.sol";
import "./../interfaces/IShareTaxPolicy.sol";
import "./ShareholderEnumerableToken.sol";
import 'OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/access/AccessControlEnumerable.sol';
import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract TransferFeeToken is AccessControlEnumerable, ShareholderEnumerableToken {
    using Address for address;

    IBlacklistPolicy public blacklistPolicy;
    IShareTaxPolicy public shareTaxPolicy;
    bool private recursionFlag;

    bytes32 public constant MAIN_ADMIN = keccak256('MAIN_ADMIN');
    bytes32 public constant CHILD_ADMIN = keccak256('CHILD_ADMIN');

    event BlacklistPolicyUpdated(address indexed oldAddress, address indexed newAddress);
    event ShareTaxPolicyUpdated(address indexed oldAddress, address indexed newAddress);

    constructor(
        string memory name_,
        string memory symbol_,
        address blacklistPolicy_,
        address admin_
    ) ShareholderEnumerableToken(name_, symbol_)
    {
        _grantRole(MAIN_ADMIN, admin_);
        _setRoleAdmin(MAIN_ADMIN, MAIN_ADMIN);
        _grantRole(CHILD_ADMIN, admin_);
        _setRoleAdmin(CHILD_ADMIN, MAIN_ADMIN);

        updateBlacklistPolicyAddress(blacklistPolicy_);
    }

    function updateBlacklistPolicyAddress(address newBlacklistPolicy)
    public onlyRole(CHILD_ADMIN)
    returns (bool success)
    {
        require(newBlacklistPolicy.isContract(), "BU");
        emit BlacklistPolicyUpdated(address(blacklistPolicy), newBlacklistPolicy);
        blacklistPolicy = IBlacklistPolicy(newBlacklistPolicy);
        success = true;
    }

    function updateShareTaxPolicyAddress(address newShareTaxPolicy)
    public onlyRole(CHILD_ADMIN)
    returns (bool success)
    {
        if (newShareTaxPolicy != address(0)) {
            require(newShareTaxPolicy.isContract());
        }
        emit ShareTaxPolicyUpdated(address(shareTaxPolicy), newShareTaxPolicy);
        shareTaxPolicy = IShareTaxPolicy(newShareTaxPolicy);
        success = true;
    }

    function transferFeeActive()
    public view
    returns (bool active)
    {
        active = address(shareTaxPolicy) != address(0);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
    internal override
    {
        // `to` is only allowed to be address(0) when it is a burn function.
        // Transfer and mint already prevent setting `to` to address(0).
        require(blacklistPolicy.transferPolicy(from, to, amount), "BU");
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
    internal override
    {
         if (transferFeeActive()
            && (from != address(0)) // exclude tax when minting
            && (to != address(0)) // exclude tax when burning
         ) {
            if (!recursionFlag) {
                recursionFlag = true;
                IShareTaxPolicy.ShareTaxTransfers[3] memory shareTaxTransfers =
                shareTaxPolicy.shareTaxActions(from, to, amount);
                for (uint i = 0; i < shareTaxTransfers.length; i++) {
                    if (shareTaxTransfers[i].amount == 0) {
                        continue;
                    }
                    _transfer(shareTaxTransfers[i].payer,
                        shareTaxTransfers[i].collector,
                        shareTaxTransfers[i].amount);
                    updateShareHolders(shareTaxTransfers[i].payer);
                    updateShareHolders(shareTaxTransfers[i].collector);
                }
                recursionFlag = false;
            }
        }
        updateShareHolders(from);
        updateShareHolders(to);
    }
}
