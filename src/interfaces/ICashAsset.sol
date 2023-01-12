// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICashAsset {
  /**
   * @notice Liquidation module can report loss when there is insolvency.
   *         This function will "print" the amount of cash to the target account
   *         and socilize the loss to everyone in the system
   *         this will result in turning on withdraw fee if the contract is indeed insolvent
   * @param lossAmountInCash Total amount of cash loss
   * @param accountToReceive Account to receive the new printed amount
   */
  function socializeLoss(uint lossAmountInCash, uint accountToReceive) external;

  ////////////////
  //   Events   //
  ////////////////

  /// @dev emitted when a user deposits to an account
  event Deposit(uint accountId, address from, uint amountCashMinted, uint stableAssetDeposited);

  /// @dev emitted when a user withdraws from an account
  event Withdraw(uint accountId, address recipient, uint amountCashBurn, uint stableAssetWidrawn);

  /// @dev emitted when withdraw fee is enabled
  ///      this would imply there is an insolvency and loss is applied to all cash holders
  event WithdrawFeeEnabled(uint exchangeRate);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error CA_NotAccount();

  /// @dev caller is not the liquidation module
  error CA_NotLiquidationModule();

  /// @dev revert when user trying to upgrade to a unknown manager
  error CA_UnknownManager();

  /// @dev caller is not owner of the account
  error CA_OnlyAccountOwner();

  /// @dev accrued interest is stale
  error CA_InterestAccrualStale(uint lastUpdatedAt, uint currentTimestamp);
}
