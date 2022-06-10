// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./TreeManagement.sol";
import "./IUniswap.sol";
import "hardhat/console.sol";

contract TestBullERC20Token is Context, IERC20, Ownable {
  using SafeMath for uint256;

  struct TreeEntity {
    string treeName;
    uint256 creationTime;
    uint256 pendingReward;
    uint256 maintenanceDeadline;
  }

  mapping (address => uint256) private _balances;
  mapping(address => mapping(address => uint256)) private _allowances;

  string private _name = "Bull Finance";
  string private _symbol = "BULL";
  uint8 private _decimals = 18;
  uint256 private _totalSupply = 10**6 * 10**_decimals; // 1 million

  uint256 private treePrice = 10 * 10**_decimals;   // 10 BULL tokens
  uint256 private bullPrice = 10; // $10

  address private treasuryPool = 0xb86CaE9Df99911d29122209fAfCCCC18a358c681;
  address private rewardPool = 0x04A0C09354f47B2f1899cC4328EDe54047b5505E;
  address public deadWallet = 0x000000000000000000000000000000000000dEaD;

  TreeManagement private treeManager;
  mapping(address => bool) private blackList;

  constructor() { 
    _balances[address(this)] = _totalSupply.mul(8).div(10);
    _balances[_msgSender()] = _totalSupply.div(10);
    _balances[rewardPool] = _totalSupply.div(10);
  }

  function name() public view returns(string memory) {
    return _name;
  }

  function symbol() public view returns(string memory) {
    return _symbol;
  }

  function totalSupply() public view override returns (uint256) {
    return _totalSupply;
  }

  function decimals() public view returns (uint8) {
      return _decimals;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account];
  }

  function transfer(address recipient, uint256 amount) public override returns (bool) {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  function allowance(address owner, address spender) public view override returns (uint256) {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount) public override returns (bool) {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  function _approve(
        address owner,
        address spender,
        uint256 amount
  ) internal {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function transferFrom(
        address sender,
        address recipient,
        uint256 amount
  ) public override returns (bool) {
    _transfer(sender, recipient, amount);

    uint256 currentAllowance = _allowances[sender][_msgSender()];
    require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
    unchecked {
        _approve(sender, _msgSender(), currentAllowance - amount);
    }

    return true;
  }

  function _transfer(address from, address to, uint256 amount) internal {
    require(from != address(0), "ERC20: transfer from the zero address");
    require(to != address(0), "ERC20: transfer to the zero address");

    uint256 senderBalance = _balances[from];
    require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
        _balances[from] = senderBalance - amount;
    }
    _balances[to] += amount;
  }


  // create tree
  //  * 10 BULL token to create a TREE.
  //  * 1 BULL is split 5:5 with BULL and MATIC. They goes liquidity pool.
  //  * 2 BULL tokens should go in treasury and should be sold for matic automatically will be owned by founders to invest it further
  //  * 7 BULL tokens should go in reward pool and should be distributed to TREE holders.
  //  *        Amount of distribution 0.225 per day. every 24 hrs to every TREE holder.
  function createTree(string memory treeName) public isBlocked {
    require(_msgSender() != address(0), "try to create tree for zero address.");
    require(balanceOf(_msgSender()) >= treePrice, "you don't have enough balance.");

    uint256 creationTime = block.timestamp;
    _transfer(_msgSender(), address(this), treePrice);

    // create Tree
    treeManager.createTree(_msgSender(), treeName, creationTime);
  }

  function claimReward(string memory name) public isBlocked payable {
    require(_msgSender() != address(0), "Token rewards to zero address.");

    uint256 time = block.timestamp;
    treeManager.updateTreeStatus(_msgSender(), time);

    uint256 numberOfTree = treeManager.getTotalCreated(_msgSender());
    require(numberOfTree > 0, "No TREE Owners.");

    uint256 claimFee = treeManager.getClaimFee();
    require(msg.value >= claimFee, "Not enough claim fee.");

    uint256 pendingRewards = treeManager.getPendingReward(_msgSender(), name, time);
    console.log("pendingreward is %s", pendingRewards);
    treeManager.updateClaimTime(_msgSender(), name, time);
    _transfer(rewardPool, _msgSender(), pendingRewards);

    uint256 unclaimedRewards = treeManager.getUnclaimedRewards();
    treeManager.formatUnclaimedRewards();
    if (unclaimedRewards > 0) {
      _transfer(rewardPool, treasuryPool, unclaimedRewards);
    }

    payable(owner()).transfer(msg.value);
  }

  // pay maintenance fee
  function payMaintenance(string memory name) public isBlocked payable {
    require(_msgSender() != address(0), "Can't pay maintenace fee from zero address.");
    uint256 maintenanceFee = treeManager.getMaintenanceFee();
    require(msg.value >= maintenanceFee, "Not enough cost.");

    treeManager.updatePaidTime(_msgSender(), name, block.timestamp);
    payable(owner()).transfer(msg.value);
  }

  function payMaintenanceAll() public isBlocked payable {
    require(_msgSender() != address(0), "Can't pay maintenace fee from zero address.");
    uint256 curTime = block.timestamp;
    uint256 maintenanceFee = treeManager.getMaintenanceFee();

    treeManager.updateAllPaidTime(_msgSender(), curTime);
    payable(owner()).transfer(msg.value);
  }

  // set maintenance duration
  function updateMaintenanceDuration(uint256 duration) public onlyOwner {
    treeManager.updateMaintenanceDuration(duration);
  }

  // get maintenance duration
  function getMaintenanceDuration() public view isBlocked returns(uint256) {
    return treeManager.getMaintenanceDuration();
  }

  function getMaintenanceDeadlineByName(string memory name) public view isBlocked returns(uint256) {
    return treeManager.getMaintenanceDeadline(_msgSender(), name);
  }

  function getTreeStatus(string memory name) public view isBlocked returns(bool) {
    uint256 curTime = block.timestamp;
    return treeManager.checkOnlyStatus(_msgSender(), name, curTime);
  }

  function setTreeManager(address managerAddress) public onlyOwner {
    treeManager = TreeManagement(managerAddress);
  }

  function addBlackList(address bannedAddress) public onlyOwner {
    blackList[bannedAddress] = true;
  }

  modifier isBlocked() {
      require(blackList[_msgSender()] == false, "This account is blocked");
      _;
  }

  function getClaimableRewards(address account) public view isBlocked returns(uint256) {
    uint256 curTime = block.timestamp;
    return treeManager.getClaimableRewards(account, curTime);
  }

  function getUserTrees(address account) public view isBlocked returns(TreeEntity[] memory) {
    uint256 curTime = block.timestamp;
    uint256 treeCount = treeManager.getTotalCreated(account);
    uint256 availableCount = treeManager.getAvailableTreeCount(account, curTime);
    TreeEntity[] memory response = new TreeEntity[](availableCount);
    uint256 index = 0;
    for (uint256 i = 0; i < treeCount; i ++) {
      if (treeManager.checkOnlyStatus(account, i, curTime) == true) {
        string memory name = treeManager.getTreeName(account, i);
        uint256 create = treeManager.getCreationTime(account, i);
        uint256 reward = treeManager.getPendingReward(account, i, curTime);
        uint256 deadline = treeManager.getDeadline(account, i);

        response[index] = TreeEntity({
          treeName: name,
          creationTime: create,
          pendingReward: reward,
          maintenanceDeadline: deadline
        });

        index = index.add(1);
      }
    }

    return response;
  }

  function buy(uint256 tokenAmount) public isBlocked payable {
    require(_msgSender() != address(0), "Zero address try to buy tokens.");
    uint256 maticPrice = getLatestPrice();
    uint256 amount = tokenAmount * 10**8;   // cuz matic price is 10**8
    uint256 desiredPrice = amount.mul(bullPrice).div(maticPrice);
    console.log("contract desiredPrice is ", desiredPrice);

    require(msg.value >= desiredPrice, "Not enough cost to buy tokens");

    payable(owner()).transfer(msg.value);
    _transfer(address(this), _msgSender(), tokenAmount);
  }

  function getLatestPrice() public view isBlocked returns (uint256) {
    return 274212922387;
  }

  function isNameExist(address account, string memory name) public view isBlocked returns (bool) {
    return treeManager.isNameExist(account, name);
  }

  function withDraw() public onlyOwner {
    uint256 amount = balanceOf(address(this));
    _transfer(address(this), _msgSender(), amount);
  }

  function withDraw(uint256 amount) public onlyOwner {
    require(balanceOf(address(this)) >= amount, "Not enough balance");
    _transfer(address(this), _msgSender(), amount);
  }

  function burn(uint256 amount) public onlyOwner {
    require(balanceOf(address(this)) >= amount, "Not enough balance.");
    _transfer(address(this), deadWallet, amount);

    _totalSupply = _totalSupply.sub(amount);
  } 

  function setCowBoyStatus(
    string[] memory treeNames, 
    uint256 rewardAmount
  ) public onlyOwner {
    uint256 creationTime = block.timestamp;
    uint16 length = uint16(treeNames.length);
    for (uint16 i = 0; i < length; i ++) {
      treeManager.updateCowBoyReward(_msgSender(), treeNames[i], rewardAmount, creationTime);
    }
  }

  receive() external payable {}
 
}