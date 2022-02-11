//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract MadibaToken is Context, IERC20, IERC20Metadata, Ownable, Pausable {
    struct HolderInfo {
        uint256 total;
        uint256 monthlyCredit;
        uint256 amountLocked;
        uint256 nextPaymentUntil;
    }

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => HolderInfo) private _whitelistInfo;
    address[] private _whitelist;
    uint256 private _newPaymentInterval = 2592000;
    uint256 private _whitelistHoldingCap = 1875000 * 10**18; // 10BNB
    uint256 private _dibaPerBNB = 187500; // current price as per the time of private sale
    uint256 private _minimumPruchaseDiba  = 3 * 10**18; // 3BNB

    address private _saleAccount;

    mapping(address => bool) public operators;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    uint256 private _cap = 1e9 * 10**18;
    uint256 public constant WHITELIST_ALLOCATION = 5e7 * 10**18; //50,000,000
    uint256 public constant PRESALE_AMOUNT = 25e7 * 10**18; //250,000,000
    uint256 public constant LIQUIDITY_ALLOCATION = 2e8 * 10**18; //200,000,000
    uint256 public constant TEAM_ALLOCATION = 3e7 * 10**18; //30,000,000
    uint256 public constant STAKING_ALLOCATION = 4e8 * 10**18; //400,000,000
    uint256 public constant REWARD_ALLOCATION = 7e7 * 10**18; //70,000,000

    uint256 public rewardReserve;
    uint256 public whitelistSaleDistributed;
    uint256 public stakingReserveUsed;
    uint256 public liquidityReserveUsed;
    uint256 public teamReserveUsed;

    address public treasuryContract;
    address public teamAddress;
    address public stakingContract;

    using SafeMath for uint256;

    event TreasuryContractChanged(
        address indexed previusAAddress,
        address indexed newAddress
    );

    event OperatorUpdated(address indexed operator, bool indexed status);

    event TeamAddressChanged(
        address indexed previusAAddress,
        address indexed newAddress
    );

    event StakingAddressChanged(
        address indexed previusAAddress,
        address indexed newAddress
    );

    modifier onlyOperator() {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }

    constructor() {
        _name = "Madiba";
        _symbol = "DIBA";
        uint256 amount = WHITELIST_ALLOCATION
            .add(PRESALE_AMOUNT)
            .add(LIQUIDITY_ALLOCATION);
        updateOperator(owner(), true);
        _mint(msg.sender, amount);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function saleAccount() public view virtual returns (address) {
        return _saleAccount;
    }

    function setSaleAddress(address _value) public onlyOwner {
        _saleAccount = _value;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
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

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function initialize(address _teamAddress) public {
      emit TeamAddressChanged(
        teamAddress,
        _teamAddress
    );
        teamAddress = _teamAddress;
    }

    function mintReward(address to) public onlyOperator {
      rewardReserve = stakingReserveUsed.add(REWARD_ALLOCATION);
        if (rewardReserve <= REWARD_ALLOCATION) {
            _mint(to, REWARD_ALLOCATION);
        }
    }

    function mint(address to, uint256 amount) external onlyOperator {
        _mint(to, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    function updateOperator(address _operator, bool _status) public onlyOwner {
        operators[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(totalSupply() + amount <= cap(), "ERC20Capped: cap exceeded");
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function claim(address account, uint256 amount) public onlyOwner {}

    function burn(address to, uint256 amount) external onlyOwner {
        _burn(to, amount);
    }

    function getOwner() external view returns (address) {
        return owner();
    }

    function setTreasuryAddress(address _newAddress)
        public
        onlyOwner
        whenNotPaused
    {
        emit TreasuryContractChanged(treasuryContract, _newAddress);
        treasuryContract = _newAddress;
    }

    function setTeamAddress(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "setDevAddress: ZERO");
        emit TeamAddressChanged(treasuryContract, _newAddress);
        teamAddress = _newAddress;
    }

    function setStakingAddress(address _newAddress) public onlyOwner {
        emit StakingAddressChanged(stakingContract, _newAddress);
        stakingContract = _newAddress;
        updateOperator(stakingContract, true);
    }

    function teamMint(uint256 _amount) public onlyOperator {
        teamReserveUsed = teamReserveUsed.add(_amount);
        if (teamReserveUsed <= TEAM_ALLOCATION) {
            _mint(teamAddress, _amount);
        }
    }

    function mintStakingReward(address _recipient, uint256 _amount)
        public
        onlyOperator
    {
        stakingReserveUsed = stakingReserveUsed.add(_amount);
        if (stakingReserveUsed <= STAKING_ALLOCATION) {
            _mint(_recipient, _amount);
        }
    }

    function registerWhitelist(address _account)
        external
        payable
    {
        require(msg.value > 0, "Invalid amount of BNB sent!");
        require(msg.value >= _minimumPruchaseDiba, "Minimum sale amount is 3BNB");
        uint256 _dibaAmount = msg.value * _dibaPerBNB;
        whitelistSaleDistributed = whitelistSaleDistributed.add(_dibaAmount);
        HolderInfo memory holder = _whitelistInfo[_account];
        if (holder.total <= 0) {
            _whitelist.push(_account);
        }
        require(
            WHITELIST_ALLOCATION >= whitelistSaleDistributed,
            "Distribution reached its max"
        );
        require(
            _whitelistHoldingCap >= holder.total.add(_dibaAmount),
            "Holding limit reached!"
        );
        payable(_saleAccount).transfer(msg.value);
        uint256 initialPayment = _dibaAmount.div(2); // Release 50% of payment
        uint256 credit = _dibaAmount.div(2);

        holder.total = holder.total.add(_dibaAmount);
        holder.amountLocked = holder.amountLocked.add(credit);
        holder.monthlyCredit = holder.amountLocked.div(5); // divide amount locked to 5 months
        holder.nextPaymentUntil = block.timestamp.add(_newPaymentInterval);
        _whitelistInfo[_account] = holder;
        _burn(owner(), _dibaAmount);
        _transfer(owner(), _account, initialPayment);
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
}
