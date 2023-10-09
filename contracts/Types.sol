//// SPDX-License-Identifier: MIT
import "./Utils.sol";

pragma solidity ^0.8.0;

abstract contract Types is Utils {


    enum RequestType { Null, Deposit, Redeem}

    struct Request {
        RequestType requestType;
        address user;
        uint256 requestAmount; // usd if request is deposit otherwise shares for redemption.
        uint256 requestFeeInUsd;
        uint256 requestTimestamp;
        uint256 processedTimestamp;
        uint256 processedAmount; // shares if request is deposit otherwise usd for redemption.
    }

    struct Portfolio {
        mapping (address => uint256) aep;
        EnumerableSet.AddressSet assets;
        uint256 flatUsd;
        uint256 leverageFactor;
    }

    struct OperationsCache {
        uint256 phase;
        RequestType requestType;
        uint256 processingLength;
        uint256 totalAmount; // total usd if request is deposit otherwise total shares for redemption.
        uint256 counter;
        uint256 aum;
        uint256 newAum;
        uint256 amountSpent;
        uint256 totalSharesToMint;
        uint256 amountReceived;
        uint256 completionCounter;
    }

    // Error codes
    /*
    e1: Must not be address 0.
    e2: Must not update a non-updatable field.
    e3: Must not exceed hard-coded limits.
    e4: Must not be int 0.
    e5: Must not have different array lengths.
    e6: Must not be empty array.
    e7: Must not exceed variable limits.
    e8: Must not process element that is not present.
    e9: Must not exceed array length.
    eA: Must be 0.
    eC: Must have enough remaining value to be processed.
    eD: Must only take place when portfolio rotation is not in progress.
    eE: Must not begin another rotation so soon after the last one ended.
    eF: Must not start when processing has not timed out yet.
    eG: Must only take place when portfolio rotation is in progress.
    eH: Must be sent from router.
    eI: Must be in the correct phase.
*/


}
