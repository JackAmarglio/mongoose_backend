// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "hardhat/console.sol";

contract TreeManagement is Context{
  using SafeMath for uint256;

  // owner
  address private manageOwner;

  // token decimal
  uint256 public tokenDecimal = 18;

  uint256 private maintenanceFee = 30; // $30

  uint256 private maintainDuration = 90 days;

  uint256 private claimFee = 5; // $5

  // distribution amount
  uint256 private unclaimedAmount = 0;
  uint256 private claimDuration = 1 days;
  uint256 private claimAmount = (2256 * 10**tokenDecimal).div(10**4); // 0.2256 BULL token

  // UserEntity
  struct TreeEntity {
    uint256 creationTime;
    uint256 lastClaimTime;
    uint256 paidTime;
    bool nftStatus;
    uint256 cowBoyRewardAmount;
    uint256 cowBoyCreationTime;
    string treeName;
  }

  mapping(address => TreeEntity[]) private userTrees;
  mapping(address => uint256) private userTreeIndex;

  constructor(address owner) {
    manageOwner = owner;
  }

  modifier onlyOwner() {
    require(manageOwner == _msgSender(), "Ownable: caller is not the owner");
    _;
  }

  function createTree(address account, string memory name, uint256 curTime) public onlyOwner {
    updateTreeStatus(account, curTime);
    userTrees[account].push(TreeEntity({
      creationTime: curTime,
      lastClaimTime: curTime,
      paidTime: curTime,
      nftStatus: false,
      cowBoyRewardAmount: 0,
      cowBoyCreationTime: 0,
      treeName: name
    }));

    userTreeIndex[account] = userTreeIndex[account].add(1);
  }

  function getPendingReward(address account, string memory name, uint256 time) public view returns (uint256) {
    uint256 index = getKeyValue(account, name, time);
    console.log("index is %s", index);
    if (index == 0) {
      return 0;
    }
    index = index.sub(1);
    return getPendingReward(account, index, time);
  }

  function getPendingReward(address account, uint256 index, uint256 time) public view returns (uint256 pendingAmount) {
    TreeEntity memory treeEntity = userTrees[account][index];
    uint256 cowBoyPendingTime = 0;
    uint256 normalPendingTime = 0;

    if (treeEntity.nftStatus == true) {
      if (treeEntity.cowBoyCreationTime >= treeEntity.lastClaimTime) {
        cowBoyPendingTime = time.sub(treeEntity.cowBoyCreationTime);
        normalPendingTime = treeEntity.cowBoyCreationTime.sub(treeEntity.lastClaimTime);
      } else {
        cowBoyPendingTime = time.sub(treeEntity.lastClaimTime);
        normalPendingTime = 0;
      }
    } else {
      cowBoyPendingTime = 0;
      normalPendingTime = time.sub(treeEntity.lastClaimTime);
    }

    pendingAmount = treeEntity.cowBoyRewardAmount.mul(cowBoyPendingTime);
    pendingAmount = pendingAmount.add(claimAmount.mul(normalPendingTime));
    pendingAmount = pendingAmount.div(claimDuration);
  }

  function updateCowBoyReward(address account, string memory _treeName, uint256 rewardAmount, uint256 time) external onlyOwner {
    uint256 index = getKeyValue(account, _treeName, time);
    if (index > 0) {
      index = index.sub(1);
      updateCowBoyReward(account, index, rewardAmount, time);
    }
  }

  function updateCowBoyReward(address account, uint256 index, uint256 rewardAmount, uint256 time) public onlyOwner {
    userTrees[account][index].cowBoyCreationTime = time;
    userTrees[account][index].cowBoyRewardAmount = rewardAmount;
    userTrees[account][index].nftStatus = true;
  }

  function getKeyValue(address account, string memory name, uint256 curTime) internal view returns(uint256) {
    for (uint256 i = 0; i < userTreeIndex[account]; i ++) {
      if (
        checkOnlyStatus(account, i, curTime) &&
        keccak256(abi.encodePacked(userTrees[account][i].treeName)) == keccak256(abi.encodePacked(name))
      ) {
        return i.add(1);        
      }
    }
    return 0;
  }

  function updateClaimTime(address account, string memory name, uint256 newTime) public onlyOwner {
    uint256 index = getKeyValue(account, name, block.timestamp);
    require(index > 0, "No such tree.");
    index = index.sub(1);
    userTrees[account][index].lastClaimTime = newTime;
  }

  // get unclaimed distribute amount of holder that can't get distribute anymore
  function getUnclaimedRewards() public view returns(uint256) {
    return unclaimedAmount;
  }

  function formatUnclaimedRewards() public onlyOwner {
    unclaimedAmount = 0;
  }

  function getClaimFee() public view returns (uint256) {
    return claimFee;
  }

  function getLastClaimTime(address account, string memory name) public view returns (uint256) {
    uint256 index = getKeyValue(account, name, block.timestamp);
    if (index == 0) {
      return 0;
    }

    index = index.sub(1);
    return userTrees[account][index].lastClaimTime;
  }

  function getDeadline(address account, uint256 index) public view returns(uint256) {
    return userTrees[account][index].paidTime.add(maintainDuration);
  }

  function updateTreeStatus(address account, uint256 time) public onlyOwner {
    uint256 i = 0;
    console.log("userTreeCount is %s", userTreeIndex[account]);
    while(true) {
      if (i == userTreeIndex[account]) {
        break;
      }
      if (checkOnlyStatus(account, i, time) == false) {
        TreeEntity memory tree = userTrees[account][i];
        uint256 deadline = getDeadline(account, i);
        uint256 restTime = deadline.sub(tree.lastClaimTime);
        uint256 amount = claimAmount.mul(restTime).div(claimDuration);      
        unclaimedAmount = unclaimedAmount.add(amount);

        delete userTrees[account][i];
      }
      i = i.add(1);
    }
  }

  function checkOnlyStatus(address account, string memory name, uint256 time) public view returns(bool) {
    if (userTreeIndex[account] == 0) {
      return false;
    }

    uint256 index = getKeyValue(account, name, time);
    if (index == 0) {
      return false;
    }

    return checkOnlyStatus(account, index.sub(1), time);
  }

  function getTotalCreated(address account) public view returns(uint256) {
    return userTreeIndex[account];
  }

  function checkOnlyStatus(address account, uint256 index, uint256 time) public view returns(bool) {
    if (userTrees[account][index].creationTime == 0) {
      return false;
    }
    if (userTreeIndex[account] == 0) {
      return false;
    }

    uint256 deadline = getDeadline(account, index);
    return deadline >= time;
  }

  function updatePaidTime(address account, string memory name, uint256 curTime) public onlyOwner {
    uint256 index = getKeyValue(account, name, curTime);
    if (index == 0) {
      return;
    }

    index = index.sub(1);

    userTrees[account][index].paidTime = userTrees[account][index].paidTime.add(maintainDuration);
  }

  function updateAllPaidTime(address account, uint256 curTime) public onlyOwner {
    uint256 createdTree = userTreeIndex[account];
    for (uint256 i = 0; i < createdTree; i ++) {
      if (checkOnlyStatus(account, i, curTime) == true) {
        userTrees[account][i].paidTime = userTrees[account][i].paidTime.add(maintainDuration);
      }
    }
  }

  function getMaintenanceDeadline(address account, string memory name) public view returns(uint256) {
    uint256 index = getKeyValue(account, name, block.timestamp);
    if (index == 0) {
      return 0;
    }

    return getDeadline(account, index.sub(1));
  }

  function updateMaintenanceDuration(uint256 newMaintenanceDuration) public onlyOwner {
    maintainDuration = newMaintenanceDuration;
  }

  function updateMaintenanceFee(uint256 newMaintenanceFee) public onlyOwner {
    maintenanceFee = newMaintenanceFee;
  }

  function getMaintenanceDuration() public view returns(uint256) {
    return maintainDuration;
  }

  function getMaintenanceFee() public view returns(uint256) {
    return maintenanceFee;
  }

  function getTreeName(address account, uint256 i) public view returns(string memory) {
    return userTrees[account][i].treeName;
  }

  function getCreationTime(address account, uint256 i) public view returns(uint256) {
    return userTrees[account][i].creationTime;
  }

  function getAvailableTreeCount(address account, uint256 curTime) public view returns(uint256) {
    if (userTreeIndex[account] == 0) {
      return 0;
    }

    uint256 treeCount = 0;
    for (uint256 i = 0; i < userTreeIndex[account]; i ++) {
      if (checkOnlyStatus(account, i, curTime) == true) {
        treeCount = treeCount.add(1);
      }
    }
    return treeCount;
  }

  function getTreeNames(address account, uint256 curTime) public view returns(string[] memory) {
    uint256 treeCount = getAvailableTreeCount(account, curTime);
    string[] memory names = new string[](treeCount);
    uint256 j = 0;
    for (uint256 i = 0; i < userTreeIndex[account]; i ++) {
      if (checkOnlyStatus(account, i, curTime) == true) {
        names[j] = userTrees[account][i].treeName;
        j = j.add(1);
      }
    }

    return names;
  }

  function getClaimableRewards(address account, uint256 curTime) public view returns(uint256) {
    uint256 claimableRewards = 0;
    for (uint256 i = 0; i < userTreeIndex[account]; i ++) {
      if (checkOnlyStatus(account, i, curTime) == true) {
        uint256 pendingReward = getPendingReward(account, i, curTime);
        claimableRewards = claimableRewards.add(pendingReward);
      }
    }

    return claimableRewards;
  }

  function isNameExist(address account, string memory name) public view returns(bool) {
    if (userTreeIndex[account] == 0) {
      return false;
    }
    uint256 index = getKeyValue(account, name, block.timestamp);
    if (index == 0) {
      return false;
    }

    return true;
  }

  function updateClaimFee(uint256 newFee) public onlyOwner {
    claimFee = newFee;
  }

  function updateClaimAmount(uint256 newClaimAmount) public onlyOwner {
    claimAmount = newClaimAmount;
  }

  function updateClaimDuration(uint256 newClaimDuration) public onlyOwner {
    claimDuration = newClaimDuration;
  }
}