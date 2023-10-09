pragma solidity ^0.8.15;

abstract contract SanctionsOracle {
    function isSanctioned(address addr) external view virtual returns (bool);
    function addToSanctionsList(address[] calldata newSanctions) external virtual;
    function isSanctionedVerbose(address addr) external virtual;
    function removeFromSanctionsList (address[] calldata removeSanctions) external virtual;
}