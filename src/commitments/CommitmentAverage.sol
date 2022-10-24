// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "../interfaces/IAccount.sol";
import "test/account/mocks/assets/lending/Lending.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * 3 Blocks to aggregate vol submited
 * * -------------- * ------------- * ------------- *
 * |   Collecting   |    Pending    |   Finalized   |
 * * -------------- * ------------- * ------------- *
 */
contract CommitmentAverage {
  // todo: need to clear deposit amount once epoch is finalized
  using SafeCast for uint;

  error No_Pending_Commitment();

  struct NodeCommitment {
    uint16 bidVol; // lets assume [256] listings for now
    uint16 askVol; // todo: still need to figure out forwards / interest
    uint128 weight; // used across all asks
    uint64 timestamp;
  }

  struct State {
    uint16 bidVol;
    uint16 askVol;
    uint128 weight;
  }

  struct Node {
    uint deposits;
    uint totalWeight;
    uint nodeId;
  }

  uint8 public COLLECTING = 0;
  uint8 public PENDING = 1;
  uint8 public FINALIZED = 2;

  mapping(uint8 => State[256]) public state; // EPOCH TYPE -> 256 epoch states
  uint64[3] public timestamps; // EPOCH TYPE -> timestamp

  // nodeData
  mapping(uint8 => mapping(uint => NodeCommitment[256])) public commitments; // epoch -> node -> commitments[], how do these work with rotating epochs
  mapping(address => Node) public nodes;
  mapping(uint => address) public nodeIdToAddress; // todo: redundant
  uint nextNodeId = 1;

  // todo: need to make dynamic range
  uint16 public constant RANGE = 5;
  uint16 public constant DEPOSIT_PER_SUBID = 500;

  // account variables
  Lending lendingAsset;
  uint accountId;
  IERC20 token;

  constructor(address _accountSystem, address _manager, address _lendingAsset, address _token) {
    lendingAsset = Lending(_lendingAsset);
    accountId = IAccount(_accountSystem).createAccount(address(this), IManager(_manager));
    token = IERC20(_token);
    token.approve(address(_lendingAsset), type(uint).max);
  }

  /// @dev allow node to deposit once and reuse deposit everytime
  function deposit(uint amount) external {
    // todo: add remove weight
    token.transferFrom(msg.sender, address(this), amount);

    lendingAsset.deposit(accountId, amount);
    Node memory depositNode = nodes[msg.sender];
    if (depositNode.nodeId == 0) {
      nodes[msg.sender].nodeId = nextNodeId;
      nodeIdToAddress[nextNodeId] = msg.sender;
      nextNodeId++;
    }

    nodes[msg.sender].deposits += amount;
  }

  /// @dev commit to the 'collecting' block
  function commit(uint16[] memory vols, uint8[] memory subIds, uint128[] memory weights) external {
    Node memory commitNode = nodes[msg.sender];

    _checkRotateBlocks();

    uint128 bidVol;
    uint128 askVol;
    for (uint i = 0; i < subIds.length; i++) {
      NodeCommitment memory subIdCommitment = commitments[COLLECTING][commitNode.nodeId][subIds[i]];

      // if commitment in current epoch was made, ignore new commitments
      if (subIdCommitment.weight > 0 && subIdCommitment.timestamp + 5 minutes > block.timestamp) break;

      // prevent further commits if not enough deposits made by node
      if (commitNode.deposits < (commitNode.totalWeight + weights[i]) * DEPOSIT_PER_SUBID) {
        break;
      } else {
        nodes[msg.sender].totalWeight += weights[i];
      }

      State memory collecting = state[COLLECTING][subIds[i]]; // get current average

      uint128 newWeight = weights[i] + collecting.weight;
      // todo: cheaper to just store in one go?
      (bidVol, askVol) = (uint128(vols[i] - RANGE), uint128(vols[i] + RANGE));
      state[COLLECTING][subIds[i]] = State({
        bidVol: SafeCast.toUint16(
          ((bidVol * weights[i]) + (uint128(collecting.bidVol) * collecting.weight)) / (newWeight)
          ),
        askVol: SafeCast.toUint16(
          ((askVol * weights[i]) + (uint128(collecting.askVol) * collecting.weight)) / (newWeight)
          ),
        weight: newWeight
      });

      commitments[COLLECTING][commitNode.nodeId][subIds[i]] =
        NodeCommitment(SafeCast.toUint16(bidVol), SafeCast.toUint16(askVol), weights[i], uint64(block.timestamp));
    }
  }

  /// @dev commit to the 'collecting' block
  function executeCommit(uint nodeId, uint128 amount, uint8 subId) external {
    // todo: deal with actual risk manager costs...
    _checkRotateBlocks();

    NodeCommitment memory nodeCommit = commitments[PENDING][nodeId][subId];

    if (nodeCommit.timestamp == 0 || nodeCommit.timestamp + 5 minutes > block.timestamp) revert No_Pending_Commitment();

    State memory avgCollecting = state[PENDING][subId];
    uint128 newWeight = avgCollecting.weight - amount;

    if (newWeight == 0) {
      state[PENDING][subId] = State(0, 0, 0); // clear average no commitments remain
    } else {
      state[PENDING][subId] = State({
        bidVol: SafeCast.toUint16(
          ((uint128(avgCollecting.bidVol) * avgCollecting.weight) - (uint128(nodeCommit.bidVol) * amount)) / (newWeight)
          ),
        askVol: SafeCast.toUint16(
          ((uint128(avgCollecting.askVol) * avgCollecting.weight) - (uint128(nodeCommit.askVol) * amount)) / (newWeight)
          ),
        weight: newWeight
      });
    }

    /* update node commitment records */
    if (amount == nodeCommit.weight) {
      commitments[PENDING][nodeId][subId] = NodeCommitment(0, 0, 0, 0);
    } else {
      commitments[PENDING][nodeId][subId].weight -= amount;
    }

    /* update node total weight */
    nodes[nodeIdToAddress[nodeId]].totalWeight -= amount;

    // trade;
    // todo: double check that deposit is actually in account
    // (1) check that cash exists
    // (2) check that cash is the only asset
  }

  /**
   * @dev clear the committed weights once epoch is finalized
   *      to allow reuse towards new commitments
   */
  function clearCommits(uint8[] memory subIds) external {
    _checkRotateBlocks();
    uint nodeId = nodes[msg.sender].nodeId;

    uint128 weightToRemove;
    for (uint subId = 0; subId < subIds.length; subId++) {
      weightToRemove += commitments[FINALIZED][nodeId][subId].weight;
    }

    nodes[msg.sender].totalWeight -= weightToRemove;
  }

  function _checkRotateBlocks() internal {
    uint64 collectingTimestamp = timestamps[COLLECTING];

    if (collectingTimestamp == 0) {
      // handle first deposit
      timestamps[COLLECTING] = SafeCast.toUint64(block.timestamp);
    } else if (collectingTimestamp + 5 minutes < block.timestamp) {
      (COLLECTING, PENDING, FINALIZED) = (FINALIZED, COLLECTING, PENDING);
    }
  }
}
