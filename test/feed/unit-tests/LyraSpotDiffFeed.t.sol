// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "./LyraFeedTestUtils.sol";

import "../../../src/feeds/LyraVolFeed.sol";
import "../../../src/feeds/LyraSpotDiffFeed.sol";
import "../../shared/mocks/MockFeeds.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_LyraSpotDiffFeed is LyraFeedTestUtils {
  MockFeeds private mockSpot;
  LyraSpotDiffFeed private feed;

  bytes32 private domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;

  function setUp() public {
    mockSpot = new MockFeeds();
    mockSpot.setSpot(990e18, 1e18);

    feed = new LyraSpotDiffFeed(ISpotFeed(address(mockSpot)));

    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);

    feed.addSigner(pkOwner, true);
  }

  function testSetSpotFeed() public {
    MockFeeds newSpotFeed = new MockFeeds();
    feed.setSpotFeed(newSpotFeed);
    assertEq(address(feed.spotFeed()), address(newSpotFeed));
  }

  function testCanPassInDataAndUpdateSpotDiffFeed() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();
    bytes memory data = _signFeedData(feed, pk, feedData);

    feed.acceptData(data);

    (uint result, uint confidence) = feed.getResult();
    assertEq(result, 1000e18);
    assertEq(confidence, 1e18);
  }

  function testCanGetSpotDiffOutsideBounds() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();

    // if 0 is expected, return the capped value
    feedData.data = abi.encode(-990e18, 1e18);
    feedData.timestamp = uint64(block.timestamp);
    feed.acceptData(_signFeedData(feed, pk, feedData));
    (uint res,) = feed.getResult();
    // res is capped at spot - 10%
    assertEq(res, 990e18 * 0.9e18 / 1e18);

    vm.warp(block.timestamp + 1);

    // even if the data would make the result negative, return the capped value
    feedData.data = abi.encode(-1000e18, 1e18);
    feedData.timestamp = uint64(block.timestamp);
    feed.acceptData(_signFeedData(feed, pk, feedData));

    (res,) = feed.getResult();
    // res is capped at spot - 10%
    assertEq(res, 990e18 * 0.9e18 / 1e18);

    vm.warp(block.timestamp + 1);

    // also works for a positive result
    feedData.data = abi.encode(1000e18, 1e18);
    feedData.timestamp = uint64(block.timestamp);
    feed.acceptData(_signFeedData(feed, pk, feedData));
    (res,) = feed.getResult();
    // res is capped at spot + 10%
    assertEq(res, 990e18 * 1.1e18 / 1e18);
  }

  function testCanUpdateSpotDiffCap() public {
    // make sure the value returned is always == spot
    feed.setSpotDiffCap(0);

    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();

    // if 0 is expected, return the capped value
    feedData.data = abi.encode(-990e18, 1e18);
    feedData.timestamp = uint64(block.timestamp);
    feed.acceptData(_signFeedData(feed, pk, feedData));
    (uint res,) = feed.getResult();
    // res is capped at spot, so diff is ignored
    assertEq(res, 990e18);

    // now 50% diff cap
    feed.setSpotDiffCap(0.5e18);
    (res,) = feed.getResult();
    assertEq(res, 495e18);

    // now 100% diff cap
    feed.setSpotDiffCap(1e18);
    (res,) = feed.getResult();
    assertEq(res, 0, "b");

    // cannot set cap beyond 100%
    vm.expectRevert(ILyraSpotDiffFeed.LSDF_InvalidSpotDiffCap.selector);
    feed.setSpotDiffCap(1.1e18);

    vm.warp(block.timestamp + 1);

    // also works for a positive result
    feedData.data = abi.encode(1000e18, 1e18);
    feedData.timestamp = uint64(block.timestamp);
    feed.acceptData(_signFeedData(feed, pk, feedData));
    (res,) = feed.getResult();
    // res is capped at spot * 2, even though diff exceeds that
    assertEq(res, 1980e18);

    feed.setSpotDiffCap(0.5e18);
    (res,) = feed.getResult();
    assertEq(res, 1485e18);

    feed.setSpotDiffCap(0);
    (res,) = feed.getResult();
    assertEq(res, 990e18);
  }

  function testCannotUpdateSpotDiffFeedFromInvalidSigner() public {
    // we didn't whitelist the pk owner this time
    feed.addSigner(pkOwner, false);

    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSigner.selector);
    feed.acceptData(data);
  }

  function testCannotUpdateSpotDiffFeedAfterDeadline() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.warp(block.timestamp + 10);

    vm.expectRevert(IBaseLyraFeed.BLF_DataExpired.selector);
    feed.acceptData(data);
  }

  function testCannotSetSpotDiffInTheFuture() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();
    feedData.timestamp = uint64(block.timestamp + 1000);
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidTimestamp.selector);
    feed.acceptData(data);
  }

  function testIgnoreUpdateIfOlderDataIsPushed() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();

    bytes memory data = _signFeedData(feed, pk, feedData);
    feed.acceptData(data);
    (, uint confidence) = feed.getResult();
    assertEq(confidence, 1e18);

    feedData.data = abi.encode(0, confidence);
    feedData.timestamp = uint64(block.timestamp - 100);
    data = _signFeedData(feed, pk, feedData);
    feed.acceptData(data);
    (, confidence) = feed.getResult();

    assertEq(confidence, 1e18);
  }

  function testCannotSubmitPriceWithReplacedSigner() public {
    // use a different private key to sign the data but still specify pkOwner as signer
    uint pk2 = 0xBEEF2222;

    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();
    feedData.signers[0] = pkOwner;
    bytes memory data = _signFeedData(feed, pk2, feedData);

    vm.expectRevert(IBaseLyraFeed.BLF_InvalidSignature.selector);
    feed.acceptData(data);
  }

  function testCannotSetInvalidConfidence() public {
    IBaseLyraFeed.FeedData memory feedData = _getDefaultSpotDiffData();
    feedData.data = abi.encode(10e18, 1.01e18);
    bytes memory data = _signFeedData(feed, pk, feedData);

    vm.expectRevert(ILyraSpotDiffFeed.LSDF_InvalidConfidence.selector);
    feed.acceptData(data);
  }

  function _getDefaultSpotDiffData() internal view returns (IBaseLyraFeed.FeedData memory data) {
    data = IBaseLyraFeed.FeedData({
      data: abi.encode(10e18, 1e18),
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });

    return data;
  }
}
