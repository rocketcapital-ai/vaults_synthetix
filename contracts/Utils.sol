//// SPDX-License-Identifier: MIT

import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/utils/structs/EnumerableSet.sol";


pragma solidity ^0.8.0;

abstract contract Utils {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(){}

    function abs(int x) internal pure returns (uint) {
    return x >= 0 ? uint(x) : uint(-x);
    }

    function getValue(int128 positionSize, uint256 avgEntryPrice, uint256 currentPrice)
    internal pure
    returns (uint256 value)
    {
        int256 pnl = (int256(currentPrice) - int256(avgEntryPrice)) * int256(positionSize);
        uint256 absPnl = abs(pnl);
        uint256 existingVolume = (abs(int256(positionSize)) * avgEntryPrice);
        value = pnl > 0 ?
            existingVolume + absPnl :
            existingVolume > absPnl ?
                existingVolume - absPnl :
                0;
        value /= 1e18;
        return value;
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
