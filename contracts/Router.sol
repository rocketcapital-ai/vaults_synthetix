//// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./OpsManager.sol";
import "./Vault.sol";
import "./Types.sol";
import 'OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/access/AccessControlEnumerable.sol';
import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/utils/structs/EnumerableSet.sol";
import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/security/ReentrancyGuard.sol";
import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/token/ERC20/utils/SafeERC20.sol";

contract Router is ReentrancyGuard, AccessControlEnumerable, Types
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20Metadata;
    using Address for address;

    EnumerableSet.AddressSet private authorizedVaults;

    bytes32 public constant MAIN_ADMIN = keccak256('MAIN_ADMIN');
    bytes32 public constant CHILD_ADMIN = keccak256('CHILD_ADMIN');

    mapping (address => uint256) public minSusdDeposit;
    mapping (address => uint256) public minSharesRedeem;

    IBlacklistPolicy public blacklistPolicy;
    event BlacklistPolicyUpdated(address indexed oldAddress, address indexed newAddress);

    constructor(address blacklistPolicy_)
    {
        _grantRole(MAIN_ADMIN, msg.sender);
        _setRoleAdmin(MAIN_ADMIN, MAIN_ADMIN);
        _grantRole(CHILD_ADMIN, msg.sender);
        _setRoleAdmin(CHILD_ADMIN, MAIN_ADMIN);
        blacklistPolicy = IBlacklistPolicy(blacklistPolicy_);
    }

    function depositRequest(address vaultAddr, uint256 amountSusd)
    external nonReentrant
    {
        require(authorizedVaults.contains(vaultAddr));
        require(amountSusd >= minSusdDeposit[vaultAddr], "Deposit amount too low.");
        require(blacklistPolicy.depositPolicy(amountSusd, 0, vaultAddr, msg.sender), "Failed blacklist check.");

        // Transfer in asset.
        Vault vault = Vault(vaultAddr);
        OpsManager om = OpsManager(vault.om());

        // Cancel previous request if any.
        RequestType rt;
        (rt,,,,,,) = om.pendingDepositRequests(msg.sender);
        if (rt == RequestType.Deposit) {
            om.cancelRequest(msg.sender, rt);
        }

        om.susd().transferFrom(msg.sender, address(om), amountSusd);
        om.onOffBoard(msg.sender, amountSusd, RequestType.Deposit);
    }

    function redeemRequest(address vaultAddr, uint256 amountShares)
    external nonReentrant
    {
        require(authorizedVaults.contains(vaultAddr));
        require(amountShares >= minSharesRedeem[vaultAddr], "Redeem amount too low.");
        require(blacklistPolicy.withdrawPolicy(0, amountShares, vaultAddr, msg.sender));

        // Transfer in shares.
        Vault vault = Vault(vaultAddr);
        OpsManager om = OpsManager(vault.om());

        // Cancel previous request if any.
        RequestType rt;
        (rt,,,,,,) = om.pendingRedeemRequests(msg.sender);
        if (rt == RequestType.Redeem) {
            om.cancelRequest(msg.sender, rt);
        }

        vault.transferFrom(msg.sender, address(om), amountShares);
        om.onOffBoard(msg.sender, amountShares, RequestType.Redeem);
    }

    function cancelDepositRequest(address vaultAddr)
    external nonReentrant
    {
        require(authorizedVaults.contains(vaultAddr));
        Vault vault = Vault(vaultAddr);
        OpsManager om = OpsManager(vault.om());
        om.cancelRequest(msg.sender, RequestType.Deposit);
    }

    function cancelRedeemRequest(address vaultAddr)
    external nonReentrant
    {
        require(authorizedVaults.contains(vaultAddr));
        Vault vault = Vault(vaultAddr);
        OpsManager om = OpsManager(vault.om());
        om.cancelRequest(msg.sender, RequestType.Redeem);
    }

    function authorizeVault(address vaultAddr)
    external onlyRole(CHILD_ADMIN)
    {
        require(vaultAddr.isContract(), "vault must be a contract.");
        authorizedVaults.add(vaultAddr);
    }

    function numberOfAuthorizedVaults()
    external view
    returns (uint256 number)
    {
        number = authorizedVaults.length();
    }

    function getAuthorizedVault(uint256 index)
    external view
    returns (address vaultAddress)
    {
        vaultAddress = authorizedVaults.at(index);
    }

    function updateBlacklistPolicyAddress(address newBlacklistPolicy)
    public onlyRole(CHILD_ADMIN)
    returns (bool success)
    {
        require(newBlacklistPolicy.isContract(), "blacklist must be a contract.");
        emit BlacklistPolicyUpdated(address(blacklistPolicy), newBlacklistPolicy);
        blacklistPolicy = IBlacklistPolicy(newBlacklistPolicy);
        success = true;
    }

    function updateMinSusdDeposit(address vaultAddr, uint256 newMinSusdDeposit)
    public onlyRole(CHILD_ADMIN)
    returns (bool success)
    {
        minSusdDeposit[vaultAddr] = newMinSusdDeposit;
        success = true;
    }

    function updateMinSharesRedeem(address vaultAddr, uint256 newMinSharesRedeem)
    public onlyRole(CHILD_ADMIN)
    returns (bool success)
    {
        minSharesRedeem[vaultAddr] = newMinSharesRedeem;
        success = true;
    }
}