//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IMadibaSwap {
    function numTokensSellToAddToLiquidity() external returns (uint256);
    function inSwapAndLiquify() external returns (bool);
    function swapAndLiquifyEnabled() external returns (bool);
    function uniswapV2Pair() external returns (address);

    function swapAndLiquify(uint256 contractTokenBalance) external;

    function mintStakingReward(address recipient, uint256 amount) external;
}
