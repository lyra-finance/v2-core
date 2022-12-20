// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/Account.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetDeposit is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  Account account;

  uint accountId;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(account));
    badManager = new MockManager(address(account));

    usdc = new MockERC20("USDC", "USDC");

    cashAsset = new CashAsset(address(account), address(usdc));

    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 18 decimals
    usdc.mint(address(this), 10000 ether);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testCannotDepositIntoWeirdAccount() public {
    uint badAccount = account.createAccount(address(this), badManager);

    vm.expectRevert(CashAsset.LA_UnknownManager.selector);
    cashAsset.deposit(badAccount, 100 ether);
  }

  function testDepositAmountMatchForFirstDeposit() public {
    uint depositAmount = 100 ether;
    cashAsset.deposit(accountId, depositAmount);

    int balance = account.getBalance(accountId, cashAsset, 0);
    assertEq(balance, int(depositAmount));
  }

  function testDepositIntoNonEmptyAccountAccrueInterest() public {
    uint depositAmount = 100 ether;
    cashAsset.deposit(accountId, depositAmount);

    vm.warp(block.timestamp + 1 days);

    // deposit again
    cashAsset.deposit(accountId, depositAmount);

    assertEq(cashAsset.lastTimestamp(), block.timestamp);
    // todo: test accrueInterest
  }
}

contract UNIT_LendingDeposit6Decimals is Test {
  CashAsset cashAsset;
  Account account;

  uint accountId;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");
    MockManager manager = new MockManager(address(account));
    MockERC20 usdc = new MockERC20("USDC", "USDC");

    // set USDC to 6 decimals
    usdc.setDecimals(6);

    cashAsset = new CashAsset(address(account), address(usdc));
    cashAsset.setWhitelistManager(address(manager), true);

    // 10000 USDC with 6 decimals
    usdc.mint(address(this), 10000e6);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = account.createAccount(address(this), manager);
  }

  function testDepositWorkWithTokensWith6Decimals() public {
    uint depositAmount = 100e6;
    cashAsset.deposit(accountId, depositAmount);

    int balance = account.getBalance(accountId, cashAsset, 0);

    // amount should be scaled to 18 decimals in account
    assertEq(balance, 100 ether);
  }
}