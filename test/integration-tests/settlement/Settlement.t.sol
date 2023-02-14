// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";
import "src/libraries/OptionEncoding.sol";

/**
 * @dev testing settlement logic
 */
contract INTEGRATION_Settlement is IntegrationTestBase {
  using DecimalMath for uint;

  address alice = address(0xaa);
  uint aliceAcc;

  address bob = address(0xbb);
  uint bobAcc;

  address charlie = address(0xcc);
  uint charlieAcc;

  // value used for test
  int constant amountOfContracts = 10e18;
  uint constant strike = 2000e18;

  uint96 callId;
  uint96 putId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    aliceAcc = accounts.createAccount(alice, pcrm);
    bobAcc = accounts.createAccount(bob, pcrm);
    charlieAcc = accounts.createAccount(charlie, pcrm);

    // allow this contract to submit trades
    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);
    vm.prank(charlie);
    accounts.setApprovalForAll(address(this), true);

    // init setup for both accounts
    _depositCash(alice, aliceAcc, DEFAULT_DEPOSIT);
    _depositCash(bob, bobAcc, DEFAULT_DEPOSIT);
    _depositCash(charlie, charlieAcc, 2e18); // initial OI Fee

    // expiry = block.timestamp + 7 days;
    expiry = block.timestamp + 4 weeks;

    callId = OptionEncoding.toSubId(expiry, strike, true);
    putId = OptionEncoding.toSubId(expiry, strike, false);
  }

  // only settle alice's account at expiry
  function testSettleShortCallImbalance() public {
    _tradeCall();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(2500e18, expiry);

    int aliceCashBefore = getCashBalance(aliceAcc);
    uint oiBefore = option.openInterest(callId);

    pcrm.settleAccount(aliceAcc);
    int aliceCashAfter = getCashBalance(aliceAcc);
    uint oiAfter = option.openInterest(callId);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    assertEq(aliceCashAfter, aliceCashBefore - expectedPayout);

    // we have net burn
    assertEq(cash.netSettledCash(), -expectedPayout);
    _assertCashSolvent();

    // total positive is the same, no change of OI
    assertEq(oiAfter, oiBefore);
  }

  // only settle bob's account after expiry
  function testSettleLongCallImbalance() public {
    _tradeCall();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(2500e18, expiry);

    int bobCashBefore = getCashBalance(bobAcc);

    pcrm.settleAccount(bobAcc);
    int bobCashAfter = getCashBalance(bobAcc);
    uint oiAfter = option.openInterest(callId);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    assertEq(bobCashAfter, bobCashBefore + expectedPayout);

    // we have net print to bob's account
    assertEq(cash.netSettledCash(), expectedPayout);
    _assertCashSolvent();

    assertEq(oiAfter, 0);
  }

  // only settle alice's account at expiry
  function testSettleShortPutImbalance() public {
    _tradePut();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(1500e18, expiry);

    int aliceCashBefore = getCashBalance(aliceAcc);

    pcrm.settleAccount(aliceAcc);
    int aliceCashAfter = getCashBalance(aliceAcc);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    assertEq(aliceCashAfter, aliceCashBefore - expectedPayout);

    // we have net burn
    assertEq(cash.netSettledCash(), -expectedPayout);

    _assertCashSolvent();
  }

  // only settle bob's account at expiry
  function testSettleLongPutImbalance() public {
    _tradePut();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(1500e18, expiry);

    int bobCashBefore = getCashBalance(bobAcc);

    pcrm.settleAccount(bobAcc);
    int bobCashAfter = getCashBalance(bobAcc);
    uint oiAfter = option.openInterest(putId);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    assertEq(bobCashAfter, bobCashBefore + expectedPayout);

    // we have net print to Bob
    assertEq(cash.netSettledCash(), expectedPayout);

    _assertCashSolvent();

    assertEq(oiAfter, 0);
  }

  // Check that after all settlements printed cash is 0
  function testPrintedCashAroundSettlements() public {
    // Alice <-> Charlie trade
    _createBorrowForUser(charlie, charlieAcc, 500e18);
    // Alice <-> Bob trade
    _tradeCall();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(2500e18, expiry);

    // Settle Bob ITM first -> increase print
    pcrm.settleAccount(bobAcc);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    // Positive due to print for Bobs ITM call
    assertEq(cash.netSettledCash(), expectedPayout);
    _assertCashSolvent();

    // Negative due to burn for Alice OTM trade
    pcrm.settleAccount(aliceAcc);
    assertLt(cash.netSettledCash(), 0);
    _assertCashSolvent();

    // Should be 0 after all trades are settled (print for charlie ITM)
    pcrm.settleAccount(charlieAcc);
    assertEq(cash.netSettledCash(), 0);
    _assertCashSolvent();

    assertEq(option.openInterest(callId), 0);
  }

  // Check interest rates and prints surrounding bob settling his account (asymmetric)
  function testInterestRateAtSettleLongCallImbalance() public {
    _createBorrowForUser(charlie, charlieAcc, 500e18);
    _tradeCall();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(2500e18, expiry);

    int bobCashBefore = getCashBalance(bobAcc);

    // Check interest accrued before settle
    uint interestAccrued =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());
    
    pcrm.settleAccount(bobAcc);
  
    console.log("IA:", interestAccrued);
    console.log("RA:", cash.totalBorrow() - 500e18);

    int bobCashAfter = getCashBalance(bobAcc);
    uint oiAfter = option.openInterest(callId);

    // payout is 500 USDC per contract
    int expectedPayout = 500 * amountOfContracts;

    // Greater than because interest is paid to Bob
    assertGt(bobCashAfter, bobCashBefore + expectedPayout);

    // we have net print to bob's account
    assertEq(cash.netSettledCash(), expectedPayout);
    _assertCashSolvent();

    uint currentBorrow = cash.totalBorrow();
    console2.log("YES:", currentBorrow);
    vm.warp(block.timestamp + 1 weeks);
    interestAccrued =
      _calculateAccruedInterestNoPrint(cash.totalSupply(), cash.totalBorrow(), block.timestamp - cash.lastTimestamp());
    cash.accrueInterest();

    // todo clarify that interest increases for the moment there is printed from settlement
    console2.log("YES:", cash.totalBorrow() - currentBorrow);
    console2.log("YES:", interestAccrued);
    // assertGt()

    assertEq(oiAfter, 0);
  }

  ///@dev alice go short, bob go long
  function _tradeCall() public {
    int premium = 500e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }

  function _tradePut() public {
    int premium = 500e18;
    // alice send put to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, putId, amountOfContracts, bobAcc, cash, 0, premium);
  }

  ///@dev create ITM call for user to borrow against
  function _createBorrowForUser(address user, uint userAcc, uint borrowAmount) internal {
    _depositCash(alice, aliceAcc, 3000e18);

    // trade ITM call for user to borrow against
    uint callStrike = 100e18;
    _submitTrade(aliceAcc, option, uint96(option.getSubId(expiry, callStrike, true)), 1e18, userAcc, cash, 0, 0);
    _withdrawCash(user, userAcc, borrowAmount);
  }

  /**
   * @notice Returns interest accrued for the given parameters.
   * @dev Used to calculate interest without netSettledCash being considered.
   * @param supply the desired supply to test
   * @param borrow the desired borrow to test
   * @param elapsedTime the time elapsed for interest accrual
   */
  function _calculateAccruedInterestNoPrint(uint supply, uint borrow, uint elapsedTime) public view returns (uint) {
    console.log("----- inside -----");
    console.log("s:", supply);
    console.log("b:", borrow);
    console.log("t:", elapsedTime);

    uint borrowRate = rateModel.getBorrowRate(supply, borrow);
    console.log("borrowRate", borrowRate);
    uint borrowInterestFactor = rateModel.getBorrowInterestFactor(elapsedTime, borrowRate);
    uint interestAccrued = borrow.multiplyDecimal(borrowInterestFactor);

    console.log("----- outside -----");
    return interestAccrued;
  }
}

// 62791525707315919
// 67729618811223981