//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../interfaces/IMadibaSwap.sol";

abstract contract BaseToken {
  struct HolderInfo {
        uint256 total;
        uint256 monthlyCredit;
        uint256 amountLocked;
        uint256 nextPaymentUntil;
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

    function decimals() public view virtual returns (uint8) {
        return 8;
    }

    function name() public view returns (string memory) {
        return  "Madiba2";
    }

    function symbol() public view returns (string memory) {
        return "DIBA2";
    }
}