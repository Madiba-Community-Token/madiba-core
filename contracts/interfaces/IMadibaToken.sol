//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IMadibaToken {
    function mint(address receiver, uint256 amount) external;

    function burn(address sender, uint256 amount) external;
    function cap() external;
    function decimals() external returns(uint8);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address sender,
        address recipient,
        uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function openApprove(address owner, address spender, uint256 amount) external returns (bool);

    function teamMint(uint256 amount) external;

    function mintStakingReward(address recipient, uint256 amount) external;

    function STAKING_RESERVE() external returns (uint256);
    function stakingReserveUsed() external returns (uint256);
}
