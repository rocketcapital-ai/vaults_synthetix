pragma solidity ^0.8.0;

contract DummyMarketSettings {
    constructor(){}

    uint256 public minKeeperFee;

    function setMinKeeperFee(uint256 _minKeeperFee) external {
        minKeeperFee = _minKeeperFee;
    }
}
