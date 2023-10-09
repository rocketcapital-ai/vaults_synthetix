// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/utils/structs/EnumerableSet.sol";
import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/token/ERC20/ERC20.sol";

abstract contract ShareholderEnumerableToken is ERC20 {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    EnumerableSet.AddressSet private shareHolders;

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

    function getShareHolders(uint256 startIndex, uint256 endIndex)
    external view
    returns (address[] memory shareHoldersList)
    {
        shareHoldersList = getListFromAddressSet(shareHolders, startIndex, endIndex);
    }

    function numberOfShareHolders()
    public view
    returns (uint256 holdersCount)
    {
        holdersCount = shareHolders.length();
    }

    function updateShareHolders(address userAddress)
    internal
    {
        if (balanceOf(userAddress) > 0) {
            shareHolders.add(userAddress);
        } else {
            shareHolders.remove(userAddress);
        }
    }

    function getListFromAddressSet(EnumerableSet.AddressSet storage setOfData, uint256 startIndex, uint256 endIndex)
    internal view
    returns (address[] memory listOfData)
    {
        if (endIndex == 0) {
            endIndex = setOfData.length();
        }
        listOfData = new address[](endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++){
            listOfData[i - startIndex] = setOfData.at(i);
        }
    }

    function getListFromUintSet(EnumerableSet.UintSet storage setOfData, uint256 startIndex, uint256 endIndex)
    internal view
    returns (uint[] memory listOfData)
    {
        if (endIndex == 0) {
            endIndex = setOfData.length();
        }
        listOfData = new uint[](endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++){
            listOfData[i - startIndex] = setOfData.at(i);
        }
    }
}
