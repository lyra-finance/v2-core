// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../../../risk-managers/mocks/MockDutchAuction.sol";
import "../mocks/MockInterestRateModel.sol";
import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";

import "../../../../src/interfaces/IDutchAuction.sol";
/**
 * @dev tests for scenarios where insolvent is triggered by the liquidation module
 */

contract UNIT_CashAssetWithdrawFee is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  SubAccounts subAccounts;
  MockDutchAuction auction;
  IInterestRateModel rateModel;

  uint accountId;
  uint depositedAmount;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));

    usdc = new MockERC20("USDC", "USDC");
    auction = new MockDutchAuction();

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(subAccounts, usdc, rateModel);
    cashAsset.setLiquidationModule(auction);

    cashAsset.setWhitelistManager(address(manager), true);

    depositedAmount = 10000 ether;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = subAccounts.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);

    assertEq(cashAsset.getCashToStableExchangeRate(), 1e18);
  }

  function testCannotTriggerInsolvencyFromAnyone() public {
    vm.expectRevert(ICashAsset.CA_NotLiquidationModule.selector);
    cashAsset.socializeLoss(depositedAmount, accountId);
  }

  function testCanTriggerInsolvencyOnce() public {
    vm.startPrank(address(auction));
    cashAsset.socializeLoss(depositedAmount, accountId);
    vm.stopPrank();

    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);

    // now 1 cash asset = 0.5 stable (USDC)
    assertEq(cashAsset.getCashToStableExchangeRate(), 0.5e18);
  }

  function testCanTriggerInsolvencyMultipleTimes() public {
    cashAsset.setSmFee(0.1e18);

    vm.startPrank(address(auction));
    assertEq(cashAsset.smFeePercentage(), 0.1e18);

    cashAsset.socializeLoss(depositedAmount / 2, accountId);
    assertEq(cashAsset.smFeePercentage(), 1e18);
    assertEq(cashAsset.previousSmFeePercentage(), 0.1e18);
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);

    cashAsset.socializeLoss(depositedAmount / 2, accountId);
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);
    assertEq(cashAsset.smFeePercentage(), 1e18);
    assertEq(cashAsset.previousSmFeePercentage(), 0.1e18);
    vm.stopPrank();

    cashAsset.setSmFee(0.1e18);

    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);

    // now 1 cash asset = 0.5 stable (USDC)
    assertEq(cashAsset.getCashToStableExchangeRate(), 0.5e18);

    usdc.mint(address(cashAsset), depositedAmount);
    cashAsset.disableWithdrawFee();
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), false);
    assertEq(cashAsset.smFeePercentage(), 0.1e18);
  }

  function testFeeIsAppliedToWithdrawAfterEnables() public {
    vm.startPrank(address(auction));
    // loss is 25% of the pool
    // meaning 1 cash is worth only 0.8% USDC after solcializing the loss
    cashAsset.socializeLoss(depositedAmount / 4, accountId);
    vm.stopPrank();

    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);
    assertEq(cashAsset.getCashToStableExchangeRate(), 0.8e18);

    uint amountUSDCToWithdraw = 100e18;
    int cashBalanceBefore = subAccounts.getBalance(accountId, cashAsset, 0);
    cashAsset.withdraw(accountId, amountUSDCToWithdraw, address(this));
    int cashBalanceAfter = subAccounts.getBalance(accountId, cashAsset, 0);

    // needs to burn 125 cash to get 100 USDC outf
    assertEq(cashBalanceBefore - cashBalanceAfter, 125e18);
  }

  function testCanDisableWithdrawFeeAfterSystemRecovers() public {
    uint smFeeCut = 0.5 * 1e18;
    cashAsset.setSmFee(smFeeCut);
    // trigger insolvency
    vm.prank(address(auction));
    cashAsset.socializeLoss(depositedAmount, accountId);

    // SM fee set to 100%
    assertEq(cashAsset.smFeePercentage(), DecimalMath.UNIT);
    // some people donate USDC to the cashAsset contract
    usdc.mint(address(cashAsset), depositedAmount);

    // disable withdraw fee
    cashAsset.disableWithdrawFee();

    assertEq(cashAsset.smFeePercentage(), smFeeCut);
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), false);
  }

  function testSmFeeCanCoverInsolvency() public {
    uint smFeeCut = 1e18;
    cashAsset.setSmFee(smFeeCut);
    uint newAccount = subAccounts.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    uint requiredAmount = 1000 * 1e18;
    cashAsset.withdraw(newAccount, requiredAmount, address(this));

    vm.warp(block.timestamp + 1 weeks);
    cashAsset.accrueInterest();
    assertEq(_checkGoldenRule(), true);

    // Assert for sm fees
    assertEq(cashAsset.accruedSmFees(), requiredAmount / 2);

    // trigger insolvency
    vm.prank(address(auction));
    cashAsset.socializeLoss(requiredAmount / 2, accountId);

    // All SM fees are enough to cover insolvency
    assertEq(cashAsset.accruedSmFees(), 0);
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), false);
    assertEq(_checkGoldenRule(), true);
  }

  function testSmFeeCanCoverSomeInsolvency() public {
    uint smFeeCut = 0.1 * 1e18;
    cashAsset.setSmFee(smFeeCut);

    uint newAccount = subAccounts.createAccount(address(this), manager);
    uint totalBorrow = cashAsset.totalBorrow();
    assertEq(totalBorrow, 0);

    // Increase total borrow amount
    uint requiredAmount = 1000 * 1e18;
    cashAsset.withdraw(newAccount, requiredAmount, address(this));

    vm.warp(block.timestamp + 1 weeks);
    cashAsset.accrueInterest();

    // Assert for sm fees
    assertGt(cashAsset.accruedSmFees(), 0);

    // trigger insolvency
    vm.prank(address(auction));

    cashAsset.socializeLoss(requiredAmount / 2, accountId);

    // All SM fees not enough to cover insolvency and insolvency still occurs
    assertEq(cashAsset.accruedSmFees(), 0);
    assertEq(cashAsset.temporaryWithdrawFeeEnabled(), true);
    assertEq(_checkGoldenRule(), false);
  }

  function _checkGoldenRule() internal view returns (bool) {
    if (
      (cashAsset.totalSupply() + cashAsset.accruedSmFees() - cashAsset.totalBorrow())
        == usdc.balanceOf(address(cashAsset))
    ) {
      return true;
    }
    return false;
  }
}
