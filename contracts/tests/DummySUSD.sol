import "OpenZeppelin/openzeppelin-contracts@4.8.0/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

pragma solidity ^0.8.0;

contract DummySUSD is ERC20PresetFixedSupply{
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address owner
    )
    ERC20PresetFixedSupply(name, symbol, initialSupply, owner)
    {}

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        address spender = _msgSender();
        _transfer(from, to, amount);
        return true;
    }
}
