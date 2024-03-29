// SPDX-License-Identifier: Unlicensed

pragma solidity >=0.8.0 <0.9.0;

interface IERC20 {
  function totalSupply() external view returns (uint256);

  function balanceOf(address account) external view returns (uint256);

  function transfer(address recipient, uint256 amount) external returns (bool);

  function allowance(address owner, address spender) external view returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface DividendPayingToken is IERC20 {
  function claim() external;
}

abstract contract Context {
  function _msgSender() internal view virtual returns (address payable) {
    return payable(msg.sender);
  }

  function _msgData() internal view virtual returns (bytes memory) {
    this;
    return msg.data;
  }
}

contract Ownable is Context {
  address private _owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  constructor () {
    address msgSender = _msgSender();
    _owner = msgSender;
    emit OwnershipTransferred(address(0), msgSender);
  }

  function owner() public view returns (address) {
    return _owner;
  }

  modifier onlyOwner() {
    require(_owner == _msgSender(), "Ownable: caller is not the owner");
    _;
  }

  function transferOwnership(address newOwner) public virtual onlyOwner() {
    require(newOwner != address(0), "Ownable: new owner is the zero address");
    emit OwnershipTransferred(_owner, newOwner);
    _owner = newOwner;
  }
}

contract TeamReflectionManager is Ownable {
  bool public canInitialize = true;

  DividendPayingToken public holdCoin;
  bool isCoinWithdrawalEnabled = false;
  mapping(address => bool) public selectiveWithdrawalEnabled;

  address public FB = 0x9E4188a7301843744fB74aE6Bcf56003DeAD629b;
  address public KS = 0xf7C1f4cA54D64542061E6f53A9D38E2f5A6A4Ecc;
  address public tempStorage = address(0);

  mapping(address => uint256) public coinHoldingOfEachWallet;
  mapping(address => uint256) public bnbWithdrawnByWallets;
  bool hasRemovedOne = false;
  uint256 public totalBNBAccumulated = 1;
  uint256 public totalCoinsPresent = 0;

  event walletUpdated (
    address oldAddress,
    address newAddress
  );

  constructor() {}

  receive() external payable {
    totalBNBAccumulated += msg.value;
  }

  function hasSystemStarted() public view returns(bool) {
    return ((holdCoin.balanceOf(address(this)) >= totalCoinsPresent) && !canInitialize);
  }

  function initializeContract(address holdCoinAddress, address[] memory _addresses, uint256[] memory _amounts) external onlyOwner() {
    require(canInitialize, "Contract already initiated");

    holdCoin = DividendPayingToken(holdCoinAddress);
    require(_addresses.length == _amounts.length, "Length Mismatch");

    for (uint256 i = 0; i < _addresses.length; i++) {
      coinHoldingOfEachWallet[_addresses[i]] = _amounts[i];
      totalCoinsPresent += _amounts[i];
    }

    canInitialize = false;
  }

  function startSystem() external {
    uint256 currentBalance = holdCoin.balanceOf(address(this));
    if (!hasSystemStarted()) {
      uint256 deficitBalance = totalCoinsPresent - currentBalance;
      require(holdCoin.allowance(_msgSender(), address(this)) >= deficitBalance, "Insufficient allowance.");
      holdCoin.transferFrom(_msgSender(), address(this), deficitBalance);
    }
  }

  function getWithdrawableBNB(address _address) public view returns(uint256) {
    uint256 totalBNBShare = (totalBNBAccumulated * coinHoldingOfEachWallet[_address]) / totalCoinsPresent;
    return totalBNBShare - bnbWithdrawnByWallets[_address];
  }

  function makeAdditionalOneCheck() internal returns(bool) {
    if (!hasRemovedOne) {
      if (totalBNBAccumulated > 1) {
        totalBNBAccumulated -= 1;
        hasRemovedOne = true;
      } else {
        return false;
      }
    }

    return true;
  }

  function withdrawDividends(address _address) private returns(bool) {
    require(hasSystemStarted(), "System has not started yet. Cannot withdraw now.");
    if (!makeAdditionalOneCheck()) {
      return false;
    }

    holdCoin.claim();
    uint256 withdrawableBNB = getWithdrawableBNB(_address);
    if (withdrawableBNB > 0) {
      (bool success, ) = address(_address).call{value : withdrawableBNB}("");
      bnbWithdrawnByWallets[_address] = bnbWithdrawnByWallets[_address] + withdrawableBNB;
    }

    return true;
  }

  function withdrawDividends() external returns(bool) {
    return withdrawDividends(_msgSender());
  }

  function setCoinWithdrawalEnable(bool isEnabled) external onlyOwner() {
    isCoinWithdrawalEnabled = isEnabled;
  }

  function setCoinWithdrawalEnableForAddress(address _address, bool isEnabled) external onlyOwner() {
    selectiveWithdrawalEnabled[_address] = isEnabled;
  }

  function ostracize(address _address) external onlyOwner() {
    require(_address != owner() && _address != FB && _address != KS && _address != tempStorage, "Cannot ostracize this wallet");

    coinHoldingOfEachWallet[tempStorage] = coinHoldingOfEachWallet[tempStorage] + coinHoldingOfEachWallet[_address];
    bnbWithdrawnByWallets[tempStorage] = bnbWithdrawnByWallets[tempStorage] + bnbWithdrawnByWallets[_address];
    coinHoldingOfEachWallet[_address] = 0;
    bnbWithdrawnByWallets[_address] = 0;
  }

  function updateFBAddress(address _address) external {
    require(_address != FB, "Address needs to be different.");
    require(_msgSender() == FB, "You are not allowed to change this address");

    coinHoldingOfEachWallet[_address] += coinHoldingOfEachWallet[FB];
    bnbWithdrawnByWallets[_address] += bnbWithdrawnByWallets[FB];
    coinHoldingOfEachWallet[FB] = 0;
    bnbWithdrawnByWallets[FB] = 0;

    FB = _address;
  }

  function updateKSAddress(address _address) external {
    require(_address != KS, "Address needs to be different.");
    require(_msgSender() == KS, "You are not allowed to change this address");

    coinHoldingOfEachWallet[_address] += coinHoldingOfEachWallet[KS];
    bnbWithdrawnByWallets[_address] += bnbWithdrawnByWallets[KS];
    coinHoldingOfEachWallet[KS] = 0;
    bnbWithdrawnByWallets[KS] = 0;

    KS = _address;
  }

  function updateTempStorageAddress(address _address) external onlyOwner() {
    require(_address != tempStorage, "Address needs to be different.");

    coinHoldingOfEachWallet[_address] += coinHoldingOfEachWallet[tempStorage];
    bnbWithdrawnByWallets[_address] += bnbWithdrawnByWallets[tempStorage];
    coinHoldingOfEachWallet[tempStorage] = 0;
    bnbWithdrawnByWallets[tempStorage] = 0;

    tempStorage = _address;
  }

  function transferOwnership(address newOwner) public override onlyOwner() {
    require(newOwner != owner(), "Address needs to be different.");

    coinHoldingOfEachWallet[newOwner] = coinHoldingOfEachWallet[owner()];
    bnbWithdrawnByWallets[newOwner] = bnbWithdrawnByWallets[owner()];
    coinHoldingOfEachWallet[owner()] = 0;
    bnbWithdrawnByWallets[owner()] = 0;

    super.transferOwnership(newOwner);
  }

  function withdrawCoins() external {
    require(hasSystemStarted(), "System has not started yet. Cannot withdraw now.");
    require(isCoinWithdrawalEnabled || selectiveWithdrawalEnabled[msg.sender], "Coin Withdrawal Not Allowed Until Enabled By Owner");

    bool success = withdrawDividends(_msgSender());
    if (success) {
      totalCoinsPresent = totalCoinsPresent - coinHoldingOfEachWallet[_msgSender()];
      totalBNBAccumulated = totalBNBAccumulated - bnbWithdrawnByWallets[_msgSender()];

      holdCoin.transfer(_msgSender(), coinHoldingOfEachWallet[_msgSender()]);

      coinHoldingOfEachWallet[_msgSender()] = 0;
      bnbWithdrawnByWallets[_msgSender()] = 0;
    }

    if (totalBNBAccumulated == 0) {
      totalBNBAccumulated = 1;
      hasRemovedOne = false;
    }
  }

  function addUserToSystem(address _address, uint256 _amount, bool allowWithdrawal) public {
    require(hasSystemStarted(), "System has not started yet. Cannot join now.");
    require(_amount > 0, "Amount has to be greater than 0.");
    require(holdCoin.allowance(_msgSender(), address(this)) >= _amount, "Insufficient Allowance");
    require(holdCoin.transferFrom(_msgSender(), address(this), _amount), "Coin transfer failed");

    if ((coinHoldingOfEachWallet[_address] <= 0) || (msg.sender == owner())) {
      selectiveWithdrawalEnabled[_address] = allowWithdrawal;
    }

    uint256 catchUpBNBShare = (totalBNBAccumulated * _amount) / totalCoinsPresent;
    coinHoldingOfEachWallet[_address] = coinHoldingOfEachWallet[_address] + _amount;
    bnbWithdrawnByWallets[_address] = bnbWithdrawnByWallets[_address] + catchUpBNBShare;
    totalBNBAccumulated = totalBNBAccumulated + catchUpBNBShare;
    totalCoinsPresent = totalCoinsPresent + _amount;
  }

  function updateUserWallet(address newAddress) external {
    coinHoldingOfEachWallet[newAddress] += coinHoldingOfEachWallet[msg.sender];
    coinHoldingOfEachWallet[msg.sender] = 0;
    bnbWithdrawnByWallets[newAddress] += bnbWithdrawnByWallets[msg.sender];
    bnbWithdrawnByWallets[msg.sender] = 0;
    selectiveWithdrawalEnabled[newAddress] = selectiveWithdrawalEnabled[newAddress] && selectiveWithdrawalEnabled[msg.sender];
    selectiveWithdrawalEnabled[msg.sender] = false;

    emit walletUpdated(msg.sender, newAddress);
  }
}
