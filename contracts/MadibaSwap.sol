//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@uniswap/lib/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IMadibaToken.sol";

contract MadibaSwap is Ownable {
    using SafeMath for uint256;
    using Address for address;

    event OperatorUpdated(address indexed operator, bool indexed status);
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    modifier onlyOperator() {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }

    mapping(address => bool) public operators;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool public inSwapAndLiquify;
    bool public swapAndLiquifyEnabled;

    uint256 public numTokensSellToAddToLiquidity;

    IMadibaToken public diba;

    constructor(IMadibaToken _diba, address router_) {
        diba = _diba;
        numTokensSellToAddToLiquidity = 175e6 * 10**diba.decimals(); // 17%
        swapAndLiquifyEnabled = false;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(router_);
        // Create a uniswap pair for this diba token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(diba), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;
        updateOperator(owner(), true);
        updateOperator(address(diba), true);
    }

    function setDiba(IMadibaToken _newdiba) public onlyOperator {
        diba = _newdiba;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOperator {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function swapAndLiquify(uint256 contractTokenBalance)
        external
        lockTheSwap
        onlyOperator
    {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(diba).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(diba).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(diba);
        path[1] = uniswapV2Router.WETH();

        diba.openApprove(address(diba), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(diba),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        diba.openApprove(address(diba), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(diba),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    function swapToToken(uint256 amount, address to) public lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(diba);
        path[1] = uniswapV2Router.WETH();

        diba.openApprove(address(diba), address(uniswapV2Router), amount);
        TransferHelper.safeApprove(
            uniswapV2Router.WETH(),
            address(diba),
            amount
        );

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0, // accept any amount of ETH
            path,
            to,
            block.timestamp
        );
    }

    function swapToEth(uint256 amount, address to) public lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(diba);
        path[1] = uniswapV2Router.WETH();

        TransferHelper.safeApprove(
            uniswapV2Router.WETH(),
            address(diba),
            amount
        );
        diba.openApprove(address(diba), address(uniswapV2Router), amount);

        uniswapV2Router.swapExactTokensForETH(
            amount,
            0, // accept any amount of ETH
            path,
            to,
            block.timestamp
        );
    }

    function updateOperator(address _operator, bool _status)
        public
        onlyOperator
    {
        operators[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }
}
