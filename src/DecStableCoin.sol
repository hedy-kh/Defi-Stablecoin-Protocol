// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedCoin is ERC20Burnable, Ownable {
    error Dec__ZeroAmount();
    error Dec__NoFunds();
    error Dec__wrongAddress();

    address payable public constant myaddress = payable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

    constructor() ERC20("DecStableCoin", "Ecoin") Ownable(myaddress) {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert Dec__ZeroAmount();
        }
        if (balance < _amount) {
            revert Dec__NoFunds();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert Dec__wrongAddress();
        }
        if (_amount <= 0) {
            revert Dec__ZeroAmount();
        }
        _mint(_to, _amount);
        return true;
    }
}
