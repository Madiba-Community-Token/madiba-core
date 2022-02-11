//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IMadibaToken {
    function mint(address receiver, uint256 amount) external;

    function burn(address sender, uint256 amount) external;
    function cap() external;

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address sender,
        address recipient,
        uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);

    function teamMint(uint256 amount) external;

    function mintStakingReward(address recipient, uint256 amount) external;

    function TEAM_ALLOCATION() external returns (uint256);

    function MARKETING_RESERVE_AMOUNT() external returns (uint256);
    function STAKING_ALLOCATION() external returns (uint256);
    function stakingReserveUsed() external returns (uint256);
}
