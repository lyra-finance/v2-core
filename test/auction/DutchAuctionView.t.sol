// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/interfaces/IDutchAuction.sol";
import "../../src/liquidation/DutchAuction.sol";
import "../../src/Account.sol";
import "../shared/mocks/MockERC20.sol";
import "../shared/mocks/MockAsset.sol";

import "../../src/liquidation/DutchAuction.sol";

import "../shared/mocks/MockManager.sol";
import "../shared/mocks/MockFeed.sol";

contract UNIT_DutchAuctionView is Test {
  
  address alice;
  address bob;
  
  uint aliceAcc;
  uint bobAcc;
  uint expiry;
  Account account;
  MockERC20 usdc;
  MockERC20 coolToken;
  MockAsset usdcAsset;
  MockAsset optionAdapter;
  MockAsset coolAsset;
  MockManager manager;
  MockFeed feed;
  DutchAuction dutchAuction;
  IDutchAuction.DutchAuctionParameters public dutchAuctionParameters;
  
  uint tokenSubId = 1000;


  function setUp() public {
    deployMockSystem();
    setupAccounts();
  }

  function setupAccounts() public {
    alice = address(0xaa);
    bob = address(0xbb);
    usdc.approve(address(usdcAsset), type(uint).max);
    // usdcAsset.deposit(ownAcc, 0, 100_000_000e18);
    aliceAcc = account.createAccount(alice, manager);
    bobAcc = account.createAccount(bob, manager);

    coolToken = new MockERC20("Cool", "COOL");
    coolAsset = new MockAsset(IERC20(coolToken), IAccount(address(account)), false);

    // give Alice usdc, and give Bob coolToken
    mintAndDeposit(alice, aliceAcc, usdc, usdcAsset, 0, 10000000e18);
    mintAndDeposit(bob, bobAcc, coolToken, coolAsset, tokenSubId, 10000000e18);

    expiry = block.timestamp + 1 days;
  }

  /// @dev deploy mock system
  function deployMockSystem() public {
    /* Base Layer */
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");

    // usdc asset: deposit with usdc, cannot be negative
    usdcAsset = new MockAsset(IERC20(usdc), IAccount(address(account)), false);
    usdcAsset = new MockAsset(IERC20(usdc), IAccount(address(account)), false);

    // optionAsset: not allow deposit, can be negative
    optionAdapter = new MockAsset(IERC20(address(0)), IAccount(address(account)), true);

    /* Risk Manager */
    manager = new MockManager(address(account));
    console.log('gets to here');
    /*
     Feed for Spot*/
    feed = new MockFeed();
    feed.setSpot(1e18 * 1000); // setting feed to 1000 usdc per eth

    dutchAuction = new DutchAuction(feed);
  }

  function mintAndDeposit(
    address user,
    uint accountId,
    MockERC20 token,
    MockAsset assetWrapper,
    uint subId,
    uint amount
  ) public {
    token.mint(user, amount);

    vm.startPrank(user);
    token.approve(address(assetWrapper), type(uint).max);
    assetWrapper.deposit(accountId, subId, amount);
    vm.stopPrank();
  }

  ///////////
  // TESTS //
  ///////////

  function testGetParams() public {
    (uint stepInterval, uint lengthOfAuction, address securityModule) = dutchAuction.parameters();
    assertEq(stepInterval, dutchAuctionParameters.stepInterval);
    assertEq(lengthOfAuction, dutchAuctionParameters.lengthOfAuction);
    assertEq(securityModule, dutchAuctionParameters.securityModule);

    // change params
    dutchAuction.setDutchAuctionParameters(IDutchAuction.DutchAuctionParameters({
      stepInterval: 2,
      lengthOfAuction: 200,
      securityModule: address(1)
    }));

    // check if params changed
    (stepInterval, lengthOfAuction, securityModule) = dutchAuction.parameters();
    assertEq(stepInterval, 2);
    assertEq(lengthOfAuction, 200);
    assertEq(securityModule, address(1));
  }

  function testGetRiskManager() public {
    assertEq(dutchAuction.isRiskManagers(address(0)), false);
    assertEq(dutchAuction.isRiskManagers(address(1)), false);
    assertEq(dutchAuction.isRiskManagers(address(2)), false);

    // setting a risk mananger
    vm.prank(address(manager));
    dutchAuction.addRiskManger();
    assertEq(dutchAuction.isRiskManagers(address(manager)), true);
  }

  function testGetSpotFeed() public {
    assertEq(address(dutchAuction.spotFeed()), address(spotFeed));
  }
} 