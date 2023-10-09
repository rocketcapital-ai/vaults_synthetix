// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "/Users/lubin/.brownie/packages/OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/token/ERC20/ERC20.sol";
import "./DummySUSD.sol";
import "./DummyMarketSettings.sol";


contract DummyPerp {
    enum OrderType {Atomic, Delayed, Offchain}

    struct Position {
        uint64 id;
        uint64 lastFundingIndex;
        uint128 margin;
        uint128 lastPrice;
        int128 size;
    }

    struct DelayedOrder {
        bool isOffchain;
        int128 sizeDelta;
        uint128 desiredFillPrice;
        uint128 targetRoundId;
        uint128 commitDeposit;
        uint128 keeperDeposit;
        uint256 executableAtTime;
        uint256 intentionTime;
        bytes32 trackingCode;
    }

    mapping (address => Position) public positionMap;
    mapping (address => DelayedOrder) public delayedOrderMap;
    DummySUSD public immutable susd;
    DummyMarketSettings public immutable marketSettings;

    uint priceOfAsset;

    constructor(address susd_, address marketSettings_) {
        susd = DummySUSD(susd_);
        marketSettings = DummyMarketSettings(marketSettings_);
    }

    function delayedOrders(address account) external view returns (DelayedOrder memory)
    {
        return delayedOrderMap[account];
    }

    function positions(address account) external view returns (Position memory)
    {
        return positionMap[account];
    }

    function transferMargin(int marginDelta) external
    {
        if (marginDelta > 0) {
            susd.transferFrom(msg.sender, address(this), uint256(marginDelta));
            positionMap[msg.sender].margin += uint128(abs(marginDelta));
        } else {
            susd.transfer(msg.sender, abs(marginDelta));
            positionMap[msg.sender].margin -= uint128(abs(marginDelta));
        }
    }

    function submitOffchainDelayedOrder(int sizeDelta, uint desiredFillPrice) external
    {
        require(sizeDelta != 0, "sizeDelta cannot be 0");
        require(positionMap[msg.sender].margin >= 50e18, "insufficient margin");
        require(delayedOrderMap[msg.sender].sizeDelta == 0, "already has delayed order");
        delayedOrderMap[msg.sender] = DelayedOrder({
            isOffchain: true,
            sizeDelta: int128(sizeDelta),
            desiredFillPrice: uint128(desiredFillPrice),
            targetRoundId: 0,
            commitDeposit: 0,
            keeperDeposit: uint128(marketSettings.minKeeperFee()),
            executableAtTime: block.timestamp + (2 minutes),
            intentionTime: block.timestamp,
            trackingCode: 0
        });
    }

    function cancelOffchainDelayedOrder(address account) external
    {
        delayedOrderMap[account] = DelayedOrder({
            isOffchain: false,
            sizeDelta: 0,
            desiredFillPrice: 0,
            targetRoundId: 0,
            commitDeposit: 0,
            keeperDeposit: 0,
            executableAtTime: 0,
            intentionTime: 0,
            trackingCode: 0
        });
    }

    function executeOrder(address account, uint128 fillPrice) external
    {
//        Position memory position = positionMap[account];
        DelayedOrder memory delayedOrder = delayedOrderMap[account];
        if (delayedOrder.isOffchain) {

            if (delayedOrder.sizeDelta > 0) {
                require(fillPrice <= delayedOrder.desiredFillPrice, "fillPrice too high");
            } else {
                require(fillPrice >= delayedOrder.desiredFillPrice, "fillPrice too low");
            }
            int128 sizeBefore = positionMap[account].size;
            int128 sizeAfter = sizeBefore + delayedOrder.sizeDelta;
            bool increase = abs(int(sizeAfter)) > abs(int(sizeBefore));
            uint sizeDelta = abs(int(delayedOrder.sizeDelta));
            positionMap[account].size = sizeAfter;
            positionMap[account].lastPrice = fillPrice;
            positionMap[account].margin -= delayedOrder.keeperDeposit;
            uint valueDelta = sizeDelta * uint(fillPrice)  / 1e18;
//            if (increase) {
//                positionMap[account].margin -= uint128(valueDelta) / 3;
//            } else {
//                positionMap[account].margin += uint128(valueDelta) / 1;
//            }
//            positionMap[account] = position;
            delayedOrderMap[account] = DelayedOrder({
                isOffchain: false,
                sizeDelta: 0,
                desiredFillPrice: 0,
                targetRoundId: 0,
                commitDeposit: 0,
                keeperDeposit: 0,
                executableAtTime: 0,
                intentionTime: 0,
                trackingCode: 0
            });
        }
    }

    function assetPrice() external view returns (uint price, bool invalid)
    {
        price = priceOfAsset;
        invalid = false;
    }

    function setAssetPrice(uint price) external
    {
        priceOfAsset = price;
    }


    function abs(int x) private pure returns (uint) {
    return x >= 0 ? uint(x) : uint(-x);
    }

}
