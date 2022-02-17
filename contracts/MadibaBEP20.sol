//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/IMadibaSwap.sol";
import "./extensions/BaseToken.sol";

contract MadibaBEP20 is IERC20, Ownable, BaseToken {
    using SafeMath for uint256;
    using Address for address;

    address public treasuryContract;
    IMadibaSwap public swapContract;

    mapping(address => HolderInfo) private _whitelistInfo;
    address[] private _whitelist;
    uint256 private _newPaymentInterval = 2592000;
    uint256 private _whitelistHoldingCap = 1875000 * 10**decimals(); // 10BNB
    uint256 private _dibaPerBNB = 187500 * 10**decimals(); // current price as per the time of private sale
    uint256 private _minimumPruchaseDiba = 3 * 10**18; // 3BNB

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) public operators;
    address[] private _excluded;

    uint256 private _totalSupply;

    uint256 public constant WHITELIST_RESERVE = 5e7 * 10**8; //50,000,000
    uint256 public constant STAKING_RESERVE = 4e8 * 10**8; //400,000,000
    uint256 public constant REWARD_RESERVE = 95e6 * 10**8; //95,000,000

    uint256 public constant PRESALE_ALLOCATION = 25e7 * 10**8; //250,000,000
    uint256 public constant LIQUIDITY_ALLOCATION = 175e6 * 10**8; //200,000,000
    uint256 public constant TEAM_ALLOCATION = 3e7 * 10**8; //30,000,000

    uint256 public rewardReserveUsed;
    uint256 public whitelistReserveUsed;
    uint256 public stakingReserveUsed;

    uint256 public _liquidityFee;
    uint256 private _previousLiquidityFee = _liquidityFee;

    uint256 public _marketingFee;
    uint256 private _previousMarketingFee = _marketingFee;

    address public _marketingFeeReceiver;
    address public stakingContract;

    uint256 private _cap = 1e9 * 10**decimals();
    uint256 public maxTxFeeBps = 4500;

    modifier onlyOperator() {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }

    constructor(
        address devAddress_,
        uint16 liquidityFeeBps_,
        uint16 marketingFeeBps_
    ) {
        require(liquidityFeeBps_ >= 0, "Invalid liquidity fee");
        require(marketingFeeBps_ >= 0, "Invalid marketing fee");
        if (devAddress_ == address(0)) {
            require(
                marketingFeeBps_ == 0,
                "Cant set both dev address to address 0 and dev percent more than 0"
            );
        }
        require(
            liquidityFeeBps_ + marketingFeeBps_ <= maxTxFeeBps,
            "Total fee is over 45%"
        );

        uint256 _initialSupply = WHITELIST_RESERVE
            .add(PRESALE_ALLOCATION)
            .add(LIQUIDITY_ALLOCATION)
            .add(TEAM_ALLOCATION);
        _mint(msg.sender, _initialSupply);

        _liquidityFee = liquidityFeeBps_;
        _previousLiquidityFee = _liquidityFee;

        _marketingFeeReceiver = devAddress_;
        _marketingFee = marketingFeeBps_;
        _previousMarketingFee = _marketingFee;

        // exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        operators[owner()] = true;
        emit OperatorUpdated(owner(), true);

        emit TokenCreated(owner(), address(this));
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function getOwner() external view returns (address) {
        return owner();
    }

    function decimals() public view virtual override returns (uint8) {
        return 8;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function openApprove(
        address owner,
        address spender,
        uint256 amount
    ) public returns (bool) {
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function mint(address _receiver, uint256 amount) public onlyOperator {
        _mint(_receiver, amount);
    }

    function burn(address to, uint256 amount) external onlyOperator {
        _burn(to, amount);
    }

    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    function _mint(address account, uint256 amount) private {
        require(totalSupply() + amount <= cap(), "ERC20Capped: cap exceeded");
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) private {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function mintReward(address to) public onlyOperator {
        rewardReserveUsed = rewardReserveUsed.add(REWARD_RESERVE);
        if (rewardReserveUsed <= REWARD_RESERVE) {
            _mint(to, REWARD_RESERVE);
        }
    }

    function mintStakingReward(address _recipient, uint256 _amount)
        public
        onlyOperator
    {
        stakingReserveUsed = stakingReserveUsed.add(_amount);
        if (stakingReserveUsed <= STAKING_RESERVE) {
            _mint(_recipient, _amount);
        }
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 tTransferAmount,
            uint256 tLiquidity,
            uint256 tMarketing,
            uint256 tDebitAmount
        ) = _getValues(tAmount);
        _balances[sender] = _balances[sender].sub(tAmount);
        _balances[recipient] = _balances[recipient].add(tAmount);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function excludeFromFee(address account) public onlyOperator {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOperator {
        _isExcludedFromFee[account] = false;
    }

    function setLiquidityFeePercent(uint256 liquidityFeeBps)
        external
        onlyOperator
    {
        _liquidityFee = liquidityFeeBps;
        require(
            _liquidityFee + _marketingFee <= maxTxFeeBps,
            "Total fee is over 45%"
        );
    }

    function setMarketingFeePercent(uint256 marketingFeeBps)
        external
        onlyOperator
    {
        _marketingFee = marketingFeeBps;
        require(
            _liquidityFee + _marketingFee <= maxTxFeeBps,
            "Total fee is over 45%"
        );
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (
            uint256 tTransferAmount,
            uint256 tLiquidity,
            uint256 tMarketing,
            uint256 tDebitAmount
        ) = _getTValues(tAmount);
        return (tTransferAmount, tLiquidity, tMarketing, tDebitAmount);
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tMarketingFee = calculateMarketingFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tLiquidity).sub(tMarketingFee);
        uint256 tDebitAmount = tAmount.add(tLiquidity).add(tMarketingFee);
        return (tTransferAmount, tLiquidity, tMarketingFee, tDebitAmount);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        _balances[address(this)] = _balances[address(this)].add(tLiquidity);
    }

    function _takeMarketingFee(uint256 tMarketing) private {
        if (tMarketing > 0) {
            _balances[_marketingFeeReceiver] = _balances[_marketingFeeReceiver]
                .add(tMarketing);
            emit Transfer(_msgSender(), _marketingFeeReceiver, tMarketing);
        }
    }

    function calculateLiquidityFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        return _amount.mul(_liquidityFee).div(10**4);
    }

    function calculateMarketingFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        if (_marketingFeeReceiver == address(0)) return 0;
        return _amount.mul(_marketingFee).div(10**4);
    }

    function removeAllFee() private {
        if (_liquidityFee == 0 && _marketingFee == 0) return;

        _previousLiquidityFee = _liquidityFee;
        _previousMarketingFee = _marketingFee;

        _liquidityFee = 0;
        _marketingFee = 0;
    }

    function restoreAllFee() private {
        _liquidityFee = _previousLiquidityFee;
        _marketingFee = _previousMarketingFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        uint256 contractTokenBalance = balanceOf(address(this));

        bool overMinTokenBalance = contractTokenBalance >=
            swapContract.numTokensSellToAddToLiquidity();
        if (
            overMinTokenBalance &&
            !swapContract.inSwapAndLiquify() &&
            from != swapContract.uniswapV2Pair() &&
            swapContract.swapAndLiquifyEnabled()
        ) {
            contractTokenBalance = swapContract.numTokensSellToAddToLiquidity();
            //add liquidity
            swapContract.swapAndLiquify(contractTokenBalance);
        }

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, takeFee);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 tTransferAmount,
            uint256 tLiquidity,
            uint256 tMarketing,
            uint256 tDebitAmount
        ) = _getValues(tAmount);
        _balances[sender] = _balances[sender].sub(tDebitAmount);
        _balances[recipient] = _balances[recipient].add(tTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeMarketingFee(tMarketing);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 tTransferAmount,
            uint256 tLiquidity,
            uint256 tMarketing,
            uint256 tDebitAmount
        ) = _getValues(tAmount);
        _balances[sender] = _balances[sender].sub(tDebitAmount);
        _balances[recipient] = _balances[recipient].add(tTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeMarketingFee(tMarketing);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 tTransferAmount,
            uint256 tLiquidity,
            uint256 tMarketing,
            uint256 tDebitAmount
        ) = _getValues(tAmount);
        _balances[sender] = _balances[sender].sub(tAmount);
        _balances[recipient] = _balances[recipient].add(tTransferAmount);
        _takeLiquidity(tLiquidity);
        _takeMarketingFee(tMarketing);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function updateOperator(address _operator, bool _status)
        public
        onlyOperator
    {
        operators[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }

    function setStakingAddress(address _newAddress) public onlyOperator {
        emit StakingAddressChanged(stakingContract, _newAddress);
        stakingContract = _newAddress;
        updateOperator(stakingContract, true);
    }

    function setMarketingAddress(address _newAddress) public onlyOperator {
        require(_newAddress != address(0), "setMarketingAddress: ZERO");
        emit MarketingAddressChanged(_marketingFeeReceiver, _newAddress);
        _marketingFeeReceiver = _newAddress;
        updateOperator(stakingContract, true);
    }

    function setTreasuryAddress(address _newAddress) public onlyOperator {
        emit TreasuryContractChanged(treasuryContract, _newAddress);
        treasuryContract = _newAddress;
    }

    function setSwapAddress(IMadibaSwap _newSwapAddress) public onlyOperator {
        emit SwapContractChanged(swapContract, _newSwapAddress);
        swapContract = _newSwapAddress;
    }

    function registerWhitelist(address _account) external payable {
        require(msg.value > 0, "Invalid amount of BNB sent!");
        require(
            msg.value >= _minimumPruchaseDiba,
            "Minimum sale amount is 3BNB"
        );
        uint256 _dibaAmount = msg.value.div(10**18).mul(_dibaPerBNB);
        whitelistReserveUsed = whitelistReserveUsed.add(_dibaAmount);
        HolderInfo memory holder = _whitelistInfo[_account];
        if (holder.total <= 0) {
            _whitelist.push(_account);
        }
        require(
            WHITELIST_RESERVE >= whitelistReserveUsed,
            "Distribution reached its max"
        );
        require(
            _whitelistHoldingCap >= holder.total.add(_dibaAmount),
            "Holding limit reached!"
        );
        payable(owner()).transfer(msg.value);
        uint256 initialPayment = _dibaAmount.div(2); // Release 50% of payment
        uint256 credit = _dibaAmount.div(2);

        holder.total = holder.total.add(_dibaAmount);
        holder.amountLocked = holder.amountLocked.add(credit);
        holder.monthlyCredit = holder.amountLocked.div(5); // divide amount locked to 5 months
        holder.nextPaymentUntil = block.timestamp.add(_newPaymentInterval);
        _whitelistInfo[_account] = holder;
        _burn(owner(), _dibaAmount);
        _mint(_account, initialPayment);
    }

    function timelyWhitelistPaymentRelease() public onlyOwner {
        for (uint256 i = 0; i < _whitelist.length; i++) {
            HolderInfo memory holder = _whitelistInfo[_whitelist[i]];
            if (
                holder.amountLocked > 0 &&
                block.timestamp >= holder.nextPaymentUntil
            ) {
                holder.amountLocked = holder.amountLocked.sub(
                    holder.monthlyCredit
                );
                holder.nextPaymentUntil = block.timestamp.add(
                    _newPaymentInterval
                );
                _whitelistInfo[_whitelist[i]] = holder;
                _mint(_whitelist[i], holder.monthlyCredit);
            }
        }
    }

    function holderInfo(address _holderAddress) public view returns(HolderInfo memory) {
      return _whitelistInfo[_holderAddress];
    }
}
