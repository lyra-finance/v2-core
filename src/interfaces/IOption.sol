// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";
import "./IInterestRateModel.sol";

interface IOption is IAsset {
  /////////////////
  //   Structs   //
  /////////////////

  struct OISnapshot {
    bool initialized;
    uint240 oi;
  }

  /// @dev Emitted when interest related state variables are updated
  event OA_SnapshotTaken(uint subId, uint tradeId, uint oi);

  ///////////////////
  //   Functions   //
  ///////////////////

  function openInterestBeforeTrade(uint subId, uint tradeId) external view returns (bool initialized, uint240 oi);

  function openInterest(uint subId) external view returns (uint oi);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev revert if caller is not Accounts
  error OA_NotAccounts();

  /// @dev revert when settlement is triggered from unknown managers
  error OA_UnknownManager();
}