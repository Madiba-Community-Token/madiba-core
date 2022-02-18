//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IMadibaSwap.sol";
import "./extensions/BaseToken.sol";

contract MadibaBEP20 is IERC20, Ownable, BaseToken {
    using SafeMath for uint256;
    using Address for address;

    address public treasuryContract;
    IMadibaSwap public swapContract;

    mapping(address => HolderInfo) private _whitelistInfo;
    address[] private _whitelist;
    uint256 private _minimumPruchaseInBNB = 3 * 10**decimals(); // 3BNB
    uint256 private _maximumPruchaseInBNB = 10 * 10**decimals(); // 10BNB
    uint256 private constant WHITELIST_RESERVE_IN_BNB = 1000 * 10**18;
    uint256 public whitelistReserveInBNBUsed;

    bool private _isWhitelistClosed = false;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    mapping(address => bool) public operators;
    address[] private _excluded;

    uint256 private _totalSupply;

    uint256 public constant WHITELIST_RESERVE = 5e7 * 10**18; //50,000,000
    uint256 public constant STAKING_RESERVE = 4e8 * 10**18; //400,000,000
    uint256 public constant REWARD_RESERVE = 95e6 * 10**18; //95,000,000

    uint256 public constant PRESALE_ALLOCATION = 25e7 * 10**18; //250,000,000
    uint256 public constant LIQUIDITY_ALLOCATION = 175e6 * 10**18; //200,000,000
    uint256 public constant TEAM_ALLOCATION = 3e7 * 10**18; //30,000,000

    uint256 public rewardReserveUsed;
    uint256 public whitelistReserveUsed;
    uint256 public stakingReserveUsed;

    uint256 public _liquidityFee;

    uint256 public _marketingFee;

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

        _marketingFeeReceiver = devAddress_;
        _marketingFee = marketingFeeBps_;

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

    function takeLiquidity(uint256 tLiquidity) external onlyOperator {
        _balances[address(this)] = _balances[address(this)].add(tLiquidity);
    }

    function takeMarketingFee(uint256 tMarketing) external onlyOperator {
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
        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {

       _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
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
        require(
           _isWhitelistClosed == false,
            "Whitelisting is no longer in session."
        );
        require(
            msg.value >= _minimumPruchaseInBNB,
            "Minimum sale amount is 3BNB"
        );
        require(msg.value <= _maximumPruchaseInBNB, "Maximum sale is 10BNB");
        HolderInfo memory holder = _whitelistInfo[_account];
        if (holder.amount <= 0) {
            _whitelist.push(_account);
        }
        require(
            WHITELIST_RESERVE_IN_BNB > whitelistReserveInBNBUsed,
            "Whitelist is no more in session."
        );
        whitelistReserveInBNBUsed = whitelistReserveInBNBUsed.add(msg.value);
        require(
            WHITELIST_RESERVE_IN_BNB >= whitelistReserveInBNBUsed,
            "Distribution reached its max"
        );
        require(
            _maximumPruchaseInBNB >= holder.amount.add(msg.value),
            "Holding limit reached!"
        );
        payable(owner()).transfer(msg.value);
        holder.amount = holder.amount.add(msg.value);
        _whitelistInfo[_account] = holder;
    }

    function closeWhitelist(uint256 dibaInBNB) public onlyOperator {
        require(_isWhitelistClosed == false, "Whitelisting is already closed.");
        _isWhitelistClosed = true;
        emit WhitelistingClosed(false, _isWhitelistClosed);
        for (uint256 i = 0; i < _whitelist.length; i++) {
            HolderInfo memory holder = _whitelistInfo[_whitelist[i]];
            uint256 tokensHeld = holder.amount.div(10**decimals()).mul(
                dibaInBNB
            );
            uint256 tokenIncludingReward = tokensHeld.add(tokensHeld.div(1)); // token including a hundred percent of token held
            whitelistReserveUsed = whitelistReserveUsed.add(
                tokenIncludingReward
            );
            if (whitelistReserveUsed > WHITELIST_RESERVE) {
                uint256 rExcess = whitelistReserveUsed.sub(WHITELIST_RESERVE);
                whitelistReserveUsed = WHITELIST_RESERVE;

                rewardReserveUsed = rewardReserveUsed.add(rExcess);
                if (rewardReserveUsed > REWARD_RESERVE) {
                    rExcess = rewardReserveUsed.sub(REWARD_RESERVE);
                    rewardReserveUsed = REWARD_RESERVE;
                    _mint(owner(), rExcess);
                }
            }
            _balances[owner()] = _balances[owner()].sub(tokenIncludingReward);
            _balances[_whitelist[i]] = _balances[_whitelist[i]].add(
                tokenIncludingReward
            );
            emit Transfer(owner(), _whitelist[i], tokenIncludingReward);
        }
    }

    function holderInfo(address _holderAddress)
        public
        view
        returns (HolderInfo memory)
    {
        return _whitelistInfo[_holderAddress];
    }
}
