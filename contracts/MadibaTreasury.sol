//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMadibaToken.sol";

contract MadibaTreasury is Ownable {
    IMadibaToken public diba;

    constructor(IMadibaToken _diba) {
        diba = _diba;
    }

    function balance() public view returns (uint256) {
        return diba.balanceOf(address(this));
    }

    function burn(uint256 amount) public onlyOwner {
        diba.burn(address(this), amount);
    }

    function setDiba(IMadibaToken _newdiba) public onlyOwner {
        diba = _newdiba;
    }
}
