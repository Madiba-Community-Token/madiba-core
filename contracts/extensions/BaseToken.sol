//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../interfaces/IMadibaSwap.sol";

abstract contract BaseToken {
  struct HolderInfo {
        uint256 amount;
    }
    
    event TokenCreated(address indexed owner, address indexed token);

    event OperatorUpdated(address indexed operator, bool indexed status);

    event StakingAddressChanged(
        address indexed previusAddress,
        address indexed newAddress
    );

    event MarketingAddressChanged(
        address indexed previusAddress,
        address indexed newAddress
    );

    event TreasuryContractChanged(
        address indexed previusAddress,
        address indexed newAddress
    );

    event SwapContractChanged(
        IMadibaSwap indexed previusAddress,
        IMadibaSwap indexed newAddress
    );

    event WhitelistingClosed(
        bool indexed previusState,
        bool indexed currentState
    );

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function name() public view virtual returns (string memory) {
        return  "Madiba";
    }

    function symbol() public view virtual returns (string memory) {
        return "DIBA";
    }
}