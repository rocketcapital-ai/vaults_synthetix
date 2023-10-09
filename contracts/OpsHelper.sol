// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IPerpsV2MarketConsolidated.sol";
import "./OpsManager.sol";

contract OpsHelper {
    constructor(){
    }

    function getAssetAepsSizes(address om, uint256 start, uint256 end)
    external view
    returns (address[] memory, uint256[] memory, int128[] memory)
    {
        address[] memory assets = OpsManager(om).getPortfolioAddresses(start, end);
        uint256[] memory aeps = OpsManager(om).getAeps(assets);
        IPerpsV2MarketConsolidated.Position[] memory positions = getPositions(om, assets);
        int128[] memory sizes = new int128[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            sizes[i] = positions[i].size;
        }
        return (assets, aeps, sizes);
    }

    function getPositions(address account, address[] memory assets)
    public view
    returns (IPerpsV2MarketConsolidated.Position[] memory)
    {
        IPerpsV2MarketConsolidated.Position[] memory positions = new IPerpsV2MarketConsolidated.Position[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            positions[i] = IPerpsV2MarketConsolidated(assets[i]).positions(address(account));
        }
        return positions;
    }

    function getAssetPrices(address[] calldata assets)
    external view
    returns (uint256[] memory)
    {
        uint256[] memory prices = new uint256[](assets.length);
        uint256 assetPrice;
        for (uint256 i = 0; i < assets.length; i++) {
            (assetPrice,) = IPerpsV2MarketConsolidated(assets[i]).assetPrice();
            prices[i] = assetPrice;
        }
        return prices;
    }

    function getDelayedOrders(address account, address[] calldata assets)
    external view
    returns (IPerpsV2MarketConsolidated.DelayedOrder[] memory)
    {
        IPerpsV2MarketConsolidated.DelayedOrder[] memory delayedOrders = new IPerpsV2MarketConsolidated.DelayedOrder[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            delayedOrders[i] = IPerpsV2MarketConsolidated(assets[i]).delayedOrders(address(account));
        }
        return delayedOrders;
    }

    function getAssetValues(address om, address[] calldata assets)
    external view
    returns (uint256[] memory)
    {
        uint256[] memory values = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            values[i] = OpsManager(om).assetValueMap(assets[i]);
        }
        return values;
    }

    function getOrderValuesForIncreasingPositions(address om, address[] calldata assets)
    external view
    returns (uint256[] memory)
    {
        uint256[] memory values = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            values[i] = OpsManager(om).orderValueForIncreasingPositionsMap(assets[i]);
        }
        return values;
    }

    function getOrderSizesForReducingPositions(address om, address[] calldata assets)
    external view
    returns (int256[] memory)
    {
        int256[] memory values = new int256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            values[i] = OpsManager(om).orderSizeForReducingPositionsMap(assets[i]);
        }
        return values;
    }

    function getKeeperFees(address om, address[] calldata assets)
    external view
    returns (uint256[] memory)
    {
        uint256[] memory values = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            values[i] = OpsManager(om).keeperFeeMap(assets[i]);
        }
        return values;
    }

    function getLastSizes(address om, address[] calldata assets)
    external view
    returns (int128[] memory)
    {
        int128[] memory values = new int128[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            values[i] = OpsManager(om).lastSizeMap(assets[i]);
        }
        return values;
    }

    function getOrderedSizes(address om, address[] calldata assets)
    external view
    returns (int256[] memory)
    {
        int256[] memory values = new int256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            values[i] = OpsManager(om).orderedSizeMap(assets[i]);
        }
        return values;
    }

    function getMarginOuts(address om, address[] calldata assets)
    external view
    returns (uint256[] memory)
    {
        uint256[] memory values = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            values[i] = OpsManager(om).marginOutMap(assets[i]);
        }
        return values;
    }

    function getCompletion(address om, address[] calldata assets)
    external view
    returns (bool[] memory)
    {
        bool[] memory values = new bool[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            values[i] = OpsManager(om).completionMap(assets[i]);
        }
        return values;
    }
}
