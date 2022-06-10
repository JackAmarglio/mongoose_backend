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

contract BullERC20Token is Context, IERC20, Ownable {
  using SafeMath for uint256;

  struct TreeEntity {
    string treeName;
    uint256 creationTime;
    uint256 pendingReward;
    uint256 maintenanceDeadline;
  }

  mapping (address => uint256) private _balances;
  mapping(address => mapping(address => uint256)) private _allowances;

  string private _name = "Mongoose";
  string private _symbol = "MGO";
  uint8 private _decimals = 18;
  uint256 private _totalSupply = 10**6 * 10**_decimals; // 1 million

  uint256 private treePrice = 10 * 10**_decimals;   // 10 BULL tokens
  uint256 private bullPrice = 10; // $10
  uint256 private sellTaxFee = 10; // 10%
  bool private sellTaxDurationEnable = true;
  uint256 private ownerLockTime = 100 days;

  address private treasuryPool = 0xb86CaE9Df99911d29122209fAfCCCC18a358c681;
  address private rewardPool = 0x562a9C382cCdA084E334e996b88f980f979a0f51;
  address public deadWallet = 0x000000000000000000000000000000000000dEaD;

  IUniswapV2Router02 public immutable uniswapV2Router; // swap address
  address public immutable uniswapV2Pair; // swap token pair
  AggregatorV3Interface internal priceFeed;

  address private cowboyAddress;
  uint256 private tokenCreatedTime;
  uint256 private ownerAllocation;

  TreeManagement private treeManager;
  mapping(address => bool) private blackList;

  modifier onlyCowBoy() {
    require(cowboyAddress == _msgSender(), "Ownable: caller is not the owner");
    _;
  }

  modifier isLocked() {
    if (_msgSender() == owner()) {
      require (block.timestamp > tokenCreatedTime.add(ownerLockTime), "Ownable: Owner can trade tokens after 100 days");
    }
    _;
  }

  constructor() { 
    ownerAllocation = _totalSupply.mul(7).div(100);
    _balances[address(this)] = _totalSupply.sub(ownerAllocation);
    _balances[_msgSender()] = ownerAllocation;
    // polygon mainnet swap router 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff 
    // polygon testnet swap router 0xbdd4e5660839a088573191A9889A262c0Efc0983 
    // uniswap router 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D 
    // polygon mainnet Aggregator address: 0xF9680D99D6C9589e2a93a78A04A279e509205945
    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

    uniswapV2Router = _uniswapV2Router;

    // rinkeby 0x8A753747A1Fa494EC906cE90E9f37563A8AF630e
    // mumbai 0x0715A7794a1dc8e42615F059dD6e406A6594651A
    priceFeed = AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e);    // polygon testnet

    tokenCreatedTime = block.timestamp;
  }

  function setCowBoyAddress(address _cowboyAddress) external onlyOwner {
    cowboyAddress = _cowboyAddress;
  }

  function setCowBoyStatus(
    string[] memory treeNames, 
    uint256 rewardAmount
  ) external onlyCowBoy {
    uint256 creationTime = block.timestamp;
    uint16 length = uint16(treeNames.length);
    for (uint16 i = 0; i < length; i ++) {
      treeManager.updateCowBoyReward(_msgSender(), treeNames[i], rewardAmount, creationTime);
    }
  }

  function setPriceFeedAddress(address feedAddress) public onlyOwner {
    priceFeed = AggregatorV3Interface(feedAddress);
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

  function transfer(address recipient, uint256 amount) public override  returns (bool) {
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

    /*if (from == owner()) {
      require (block.timestamp > tokenCreatedTime.add(ownerLockTime), "Ownable: Owner can trade tokens after 100 days");
    }*/

    uint256 senderBalance = _balances[from];
    require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
        _balances[from] = senderBalance - amount;
    }
    _balances[to] += amount;
  }

  function buy(uint256 tokenAmount) public isBlocked payable {
    require(_msgSender() != address(0), "Zero address try to buy tokens.");
    uint256 maticPrice = getLatestPrice();
    uint256 amount = tokenAmount * 10**8;   // cuz matic price is 10**8
    uint256 desiredPrice = amount.mul(bullPrice).div(maticPrice);

    require(msg.value >= desiredPrice, "Not enough cost to buy tokens");

    payable(owner()).transfer(msg.value);
    _transfer(address(this), _msgSender(), tokenAmount);
  }

  function sell(uint256 tokenAmount) public isBlocked {
    require(_msgSender() != address(0), "Zero address try to sell tokens.");
    require(balanceOf(_msgSender()) >= tokenAmount, "Not enough balance.");

    uint256 sellTaxFee_ = tokenAmount.div(sellTaxFee);
    tokenAmount = tokenAmount.sub(sellTaxFee_);

    _transfer(_msgSender(), address(this), tokenAmount);
    _transfer(_msgSender(), treasuryPool, sellTaxFee_);
    
    _approve(address(this), address(uniswapV2Router), tokenAmount);

    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount, 
      0, 
      path, 
      _msgSender(), 
      block.timestamp
    );
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

    swapAndLiquidify(1 * 10**_decimals);    // 1 BULL
    addTreasuryPool(2 * 10**_decimals);     // 2 BULL
    addRewardPool(address(this), 7 * 10**_decimals); // 7 BULL

    // create Tree
    treeManager.createTree(_msgSender(), treeName, creationTime);
  }

  // create node - 1 BULL process: add liquidity (50% BULL, 50% MATIC)
  function swapAndLiquidify(uint256 tokenAmount) private {
    uint256 half = tokenAmount.div(2);
    uint256 otherHalf = tokenAmount.sub(half);

    // initial MATIC balance
    uint256 initialBalance = address(this).balance;

    swapTokensForMATIC(half);
    uint256 swapMaticAmount = address(this).balance.sub(initialBalance);

    // add liquidity
    addLiquidity(otherHalf, swapMaticAmount);
  }

  // create node - 2 BULL process: be sold and send to owner
  function addTreasuryPool(uint256 tokenAmount) private {
    uint256 initialBalance = address(this).balance;
    swapTokensForMATIC(tokenAmount);

    uint256 swapMaticAmount = address(this).balance.sub(initialBalance);
    payable(treasuryPool).transfer(swapMaticAmount);
  }

  // create node - 7 BULL process: go to reward pool
  function addRewardPool(address sender, uint256 tokenAmount) private {
    _transfer(sender, rewardPool, tokenAmount);
  }

  // swap BULL to token
  function swapTokensForMATIC(uint256 tokenAmount) private {
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    _approve(address(this), address(uniswapV2Router), tokenAmount);

    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount, 
      0, 
      path, 
      address(this), 
      block.timestamp
    );
  }

  function makeLiquidity(uint256 tokenAmount) external payable {
    _approve(_msgSender(), address(uniswapV2Router), tokenAmount);

    uniswapV2Router.addLiquidityETH{value: msg.value}(
      address(this), 
      tokenAmount, 
      0, 
      0, 
      _msgSender(), 
      block.timestamp + 360
    );
  }

  // add liquidity (MATIC, BULL)
  function addLiquidity(uint256 tokenAmount, uint256 maticAmount) private {
    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // add the liquidity
    uniswapV2Router.addLiquidityETH{value: maticAmount}(
      address(this),
      tokenAmount,
      0,
      0,
      owner(),
      block.timestamp + 360
    );
  }

  function claimReward(string memory name_) public isBlocked payable {
    require(_msgSender() != address(0), "Token rewards to zero address.");

    uint256 time = block.timestamp;
    treeManager.updateTreeStatus(_msgSender(), time);

    uint256 numberOfTree = treeManager.getAvailableTreeCount(_msgSender(), time);
    require(numberOfTree > 0, "No TREE Owners.");

    uint256 claimFee = treeManager.getClaimFee();
    uint256 maticPrice = getLatestPrice();
    uint256 desiredPrice = claimFee.mul(10**18 * 10**8).div(maticPrice);
    require(msg.value >= desiredPrice, "Not enough claim fee.");

    uint256 pendingRewards = treeManager.getPendingReward(_msgSender(), name_, time);
    treeManager.updateClaimTime(_msgSender(), name_, time);
    _transfer(rewardPool, _msgSender(), pendingRewards);

    uint256 unclaimedRewards = treeManager.getUnclaimedRewards();
    treeManager.formatUnclaimedRewards();
    if (unclaimedRewards > 0) {
      _transfer(rewardPool, treasuryPool, unclaimedRewards);
    }

    payable(owner()).transfer(msg.value);
  }

  // pay maintenance fee
  function payMaintenance(string memory name_) public isBlocked payable {
    require(_msgSender() != address(0), "Can't pay maintenace fee from zero address.");
    uint256 maintenanceFee = treeManager.getMaintenanceFee();
    uint256 maticPrice = getLatestPrice();
    uint256 desiredPrice = maintenanceFee.mul(10**18 * 10**8).div(maticPrice);
    require(msg.value >= desiredPrice, "Not enough cost.");

    treeManager.updatePaidTime(_msgSender(), name_, block.timestamp);
    payable(owner()).transfer(msg.value);
  }

  function payMaintenanceAll() public isBlocked payable {
    require(_msgSender() != address(0), "Can't pay maintenace fee from zero address.");
    uint256 curTime = block.timestamp;
    uint256 maintenanceFee = treeManager.getMaintenanceFee();
    uint256 maticPrice = getLatestPrice();
    uint256 desiredPrice = maintenanceFee.mul(10**18 * 10**8).div(maticPrice);
    uint256 treeAmount = treeManager.getAvailableTreeCount(_msgSender(), curTime);
    desiredPrice = desiredPrice.mul(treeAmount);
    require(msg.value >= desiredPrice, "Not enough cost.");

    treeManager.updateAllPaidTime(_msgSender(), curTime);
    payable(owner()).transfer(msg.value);
  }

  function updateMaintenanceDuration(uint256 duration) public onlyOwner {
    treeManager.updateMaintenanceDuration(duration);
  }

  function udpateMaintenanceFee(uint256 fee) public onlyOwner {
    treeManager.updateMaintenanceFee(fee);
  }

  function updateClaimFee(uint256 fee) public onlyOwner {
    treeManager.updateClaimFee(fee);
  }

  function updateClaimDuration(uint256 duration) public onlyOwner {
    treeManager.updateClaimDuration(duration);
  }

  // get maintenance duration
  function getMaintenanceDuration() public view isBlocked returns(uint256) {
    return treeManager.getMaintenanceDuration();
  }

  function getMaintenanceDeadlineByName(string memory name_) public view isBlocked returns(uint256) {
    return treeManager.getMaintenanceDeadline(_msgSender(), name_);
  }

  function getTreeStatus(string memory name_) public view isBlocked returns(bool) {
    uint256 curTime = block.timestamp;
    return treeManager.checkOnlyStatus(_msgSender(), name_, curTime);
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
        string memory name_ = treeManager.getTreeName(account, i);
        uint256 create = treeManager.getCreationTime(account, i);
        uint256 reward = treeManager.getPendingReward(account, i, curTime);
        uint256 deadline = treeManager.getDeadline(account, i);

        response[index] = TreeEntity({
          treeName: name_,
          creationTime: create,
          pendingReward: reward,
          maintenanceDeadline: deadline
        });

        index = index.add(1);
      }
    }

    return response;
  }

  function isNameExist(address account, string memory name_) public view isBlocked returns (bool) {
    return treeManager.isNameExist(account, name_);
  }

  function getLatestPrice() public view isBlocked returns (uint256) {
    (
        uint80 roundID, 
        int price,
        uint startedAt,
        uint timeStamp,
        uint80 answeredInRound
    ) = priceFeed.latestRoundData();
    return uint256(price);
  }

  function getTreeCount(address account) public view returns(uint256) {
    uint256 curTime = block.timestamp;
    return treeManager.getAvailableTreeCount(account, curTime);
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

  receive() external payable {}
 
}