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
  address alice = address(0xaa);
  uint aliceAcc;

  address bob = address(0xbb);
  uint bobAcc;

  // value used for test
  uint constant initCash = 3000e18;
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

    // allow this contract to submit trades
    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);

    // init setup for both accounts
    _depositCash(alice, aliceAcc, initCash);
    _depositCash(bob, bobAcc, initCash);

    expiry = block.timestamp + 7 days;

    callId = OptionEncoding.toSubId(expiry, strike, true);
    putId = OptionEncoding.toSubId(expiry, strike, false);
  }

  // only settle alice's account at expiry
  function testSettleShortCallImbalance() public {
    _assertCashSolvent();

    _tradeCall();

    // stimulate expiry price
    vm.warp(expiry);
    _setSpotPriceAndSubmitForExpiry(2500e18, expiry);

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

  // only settle alice's account at expiry
  // function testSettleShortPutImbalance() public {
  //  //todo: conform init margin for put
  //   _tradePut();

  //   // stimulate expiry price
  //   vm.warp(expiry);
  //   _setSpotPriceAndSubmitForExpiry(1500e18, expiry);

  //   int aliceCashBefore = getCashBalance(aliceAcc);

  //   pcrm.settleAccount(aliceAcc);
  //   int aliceCashAfter = getCashBalance(aliceAcc);

  //   // payout is 500 USDC per contract
  //   int expectedPayout = 500 * amountOfContracts;

  //   assertEq(aliceCashAfter, aliceCashBefore - expectedPayout);

  //   // we have net burn
  //   assertEq(cash.netSettledCash(), -expectedPayout);

  //   _assertCashSolvent();
  // }

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
}
