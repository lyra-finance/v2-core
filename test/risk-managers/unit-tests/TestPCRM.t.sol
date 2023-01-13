pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";
import "test/shared/mocks/MockManager.sol";
import "test/risk-managers/mocks/MockDutchAuction.sol";

contract UNIT_TestPCRM is Test {
  Accounts account;
  PCRM manager;

  ChainlinkSpotFeeds spotFeeds; //todo: should replace with generic mock
  MockV3Aggregator aggregator;
  Option option;
  MockDutchAuction auction;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);

    auction = new MockDutchAuction();

    option = new Option();
    manager = new PCRM(
      address(account),
      address(spotFeeds),
      address(0), // lending
      address(option),
      address(auction)
    );

    manager.setParams(
      PCRM.Shocks({
        spotUpInitial: 120e16,
        spotDownInitial: 80e16,
        spotUpMaintenance: 110e16,
        spotDownMaintenance: 90e16,
        vol: 300e16,
        rfr: 10e16
      }),
      PCRM.Discounts({maintenanceStaticDiscount: 90e16, initialStaticDiscount: 80e16})
    );

    vm.startPrank(alice);
    aliceAcc = account.createAccount(alice, IManager(manager));
    bobAcc = account.createAccount(bob, IManager(manager));
    vm.stopPrank();

    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();
  }

  ///////////
  // Admin //
  ///////////

  function testSetParamsWithNonOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(AbstractOwned.OnlyOwner.selector, address(manager), alice, manager.owner()));
    manager.setParams(
      PCRM.Shocks({
        spotUpInitial: 120e16,
        spotDownInitial: 80e16,
        spotUpMaintenance: 110e16,
        spotDownMaintenance: 90e16,
        vol: 300e16,
        rfr: 10e16
      }),
      PCRM.Discounts({maintenanceStaticDiscount: 90e16, initialStaticDiscount: 80e16})
    );
    vm.stopPrank();
  }

  function testSetParamsWithOwner() public {
    manager.setParams(
      PCRM.Shocks({
        spotUpInitial: 200e16,
        spotDownInitial: 50e16,
        spotUpMaintenance: 120e16,
        spotDownMaintenance: 70e16,
        vol: 400e16,
        rfr: 20e16
      }),
      PCRM.Discounts({maintenanceStaticDiscount: 85e16, initialStaticDiscount: 75e16})
    );

    (uint spotUpInitial, uint spotDownInitial, uint spotUpMaintenance, uint spotDownMaintenance, uint vol, uint rfr) =
      manager.shocks();
    assertEq(spotUpInitial, 200e16);
    assertEq(spotDownInitial, 50e16);
    assertEq(spotUpMaintenance, 120e16);
    assertEq(spotDownMaintenance, 70e16);
    assertEq(vol, 400e16);
    assertEq(rfr, 20e16);

    (uint maintenanceStaticDiscount, uint initialStaticDiscount) = manager.discounts();
    assertEq(maintenanceStaticDiscount, 85e16);
    assertEq(initialStaticDiscount, 75e16);
  }

  //////////////
  // Transfer //
  //////////////

  function testHandleAdjustment() public {
    vm.startPrank(alice);
    AccountStructs.AssetTransfer memory assetTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: 1,
      amount: 1e18,
      assetData: ""
    });
    account.submitTransfer(assetTransfer, "");
    vm.stopPrank();

    // todo: actually do manager
  }

  /////////////////////////
  // Margin calculations //
  /////////////////////////

  function testEmptyInitialMarginCalculation() public view {
    PCRM.StrikeHolding[] memory strikes = new PCRM.StrikeHolding[](1);
    strikes[0] = PCRM.StrikeHolding({strike: 0, calls: 0, puts: 0, forwards: 0});

    PCRM.ExpiryHolding memory expiry = PCRM.ExpiryHolding({expiry: 0, numStrikesHeld: 0, strikes: strikes});

    manager.getInitialMargin(expiry, 0);

    // todo: actually test
  }

  function testEmptyMaintenanceMarginCalculation() public view {
    PCRM.StrikeHolding[] memory strikes = new PCRM.StrikeHolding[](1);
    strikes[0] = PCRM.StrikeHolding({strike: 0, calls: 0, puts: 0, forwards: 0});

    PCRM.ExpiryHolding memory expiry = PCRM.ExpiryHolding({expiry: 0, numStrikesHeld: 0, strikes: strikes});

    manager.getMaintenanceMargin(expiry, 0);

    // todo: actually test
  }

  function testInitialMarginCalculation() public view {
    PCRM.StrikeHolding[] memory strikes = new PCRM.StrikeHolding[](2);
    strikes[0] = PCRM.StrikeHolding({strike: 1000e18, calls: 1e18, puts: 0, forwards: 0});
    strikes[1] = PCRM.StrikeHolding({strike: 0e18, calls: 1e18, puts: 0, forwards: 0});

    PCRM.ExpiryHolding memory expiry = PCRM.ExpiryHolding({expiry: block.timestamp + 1 days, numStrikesHeld: 2, strikes: strikes});

    manager.getInitialMargin(expiry, 0);

    // todo: actually test
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  function testValidManagerChange() public {
    MockManager newManager = new MockManager(address(account));

    // todo: test change to valid manager
    vm.startPrank(address(alice));
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();
  }

  //////////////////
  // Liquidations //
  //////////////////

  function testCheckAndStartLiquidation() public {
    manager.checkAndStartLiquidation(aliceAcc);
  }

  function testExecuteBid() public {
    vm.startPrank(address(auction));
    manager.executeBid(aliceAcc, 0, 5e17, 0);
    vm.stopPrank();
  }

  //////////
  // View //
  //////////

  function testGetGroupedOptions() public {
    _openDefaultOptions();

    (PCRM.ExpiryHolding memory holding) = manager.getGroupedOptions(aliceAcc);
    assertEq(holding.strikes[0].strike, 1000e18);
    assertEq(holding.strikes[0].calls, 0);
    assertEq(holding.strikes[0].puts, -9e18);
    assertEq(holding.strikes[0].forwards, 1e18);
  }

  function _openDefaultOptions() internal {
    vm.startPrank(address(alice));
    uint callSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, true);

    uint putSubId = OptionEncoding.toSubId(block.timestamp + 1 days, 1000e18, false);

    uint longtermSubId = OptionEncoding.toSubId(block.timestamp + 365 days, 10e18, false);

    AccountStructs.AssetTransfer memory callTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: callSubId,
      amount: 1e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer memory putTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: putSubId,
      amount: -10e18,
      assetData: ""
    });
    AccountStructs.AssetTransfer memory longtermTransfer = AccountStructs.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: IAsset(option),
      subId: longtermSubId,
      amount: 5e18,
      assetData: ""
    });
    account.submitTransfer(callTransfer, "");
    account.submitTransfer(putTransfer, "");
    account.submitTransfer(longtermTransfer, "");

    vm.stopPrank();
  }
}
