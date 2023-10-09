// SPDX-License-Identifier: No license

pragma solidity ^0.8.15;

contract AtomicCall {
    constructor(){}

    event Call(bool success, bytes returnedData, address callee, bytes calleeData);

    function atomicCall(address[] calldata addresses, bytes[] calldata data)
    external
    returns (bytes[] memory)
    {
        bytes[] memory returnDataList = new bytes[](data.length);
        for (uint i = 0; i < data.length; i++){
            (bool success, bytes memory returnedData) = addresses[i].call(data[i]);

            // The below chunk is taken from https://ethereum.stackexchange.com/a/83577.
            if (!success) {
                if (returnedData.length < 68) revert();
                assembly {
                    returnedData := add(returnedData, 0x04)
                }
                revert(abi.decode(returnedData, (string)));
            }
            // end of chunk

            emit Call(success, returnedData, addresses[i], data[i]);
            returnDataList[i] = returnedData;
        }
        return returnDataList;
    }
}
