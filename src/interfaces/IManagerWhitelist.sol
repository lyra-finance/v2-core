// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IManagerWhitelist {
  ////////////////
  //   Events   //
  ////////////////

  event WhitelistManagerSet(address _manager, bool _whitelisted);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error MW_OnlyAccounts();

  /// @dev revert when user trying to upgrade to a unknown manager
  error MW_UnknownManager();
}
