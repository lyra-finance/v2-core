// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/ISpotFeeds.sol";
import "src/libraries/DecimalMath.sol";
import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "openzeppelin/utils/math/SafeCast.sol";

contract ChainlinkSpotFeeds is ISpotFeeds {
  /* only 1x SLOAD when getting price */
  struct Aggregator {
    // address of chainlink aggregator
    AggregatorV3Interface aggregator;
    // decimal units of returned spot price
    uint8 decimals;
    // stale limit in seconds
    uint64 staleLimit;
  }

  ///////////////
  // Variables //
  ///////////////

  /// @dev maps feedId to trading pair symbol
  mapping(uint => bytes32) public feedIdToSymbol;

  /// @dev first id starts from 1
  uint public lastFeedId;
  /// @dev maps feedId to aggregator details
  mapping(uint => Aggregator) public aggregators;

  ////////////
  // Events //
  ////////////

  // todo: add events

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor() {}

  ///////////////
  // Get Price //
  ///////////////

  /**
   * @notice Gets spot price for a given feedId
   * @param feedId id set for a given trading pair
   * @return spotPrice 18 decimal price of trading pair
   */
  function getSpot(uint feedId) external view returns (uint) {
    (uint spotPrice, uint updatedAt) = getSpotAndUpdatedAt(feedId);

    uint currentTime = block.timestamp;
    uint staleLimit = aggregators[feedId].staleLimit;
    if (currentTime - updatedAt > staleLimit) {
      revert SF_SpotFeedStale(updatedAt, currentTime, staleLimit);
    } 

    return spotPrice;
  }

  /**
   * @notice Uses chainlinks `AggregatorV3` oracles to retrieve price.
   *         The price is always converted to an 18 decimal uint
   * @param feedId id set for a given trading pair
   * @return spotPrice 18 decimal price of trading pair
   * @return updatedAt timestamp of update
   */
  function getSpotAndUpdatedAt(uint feedId) public view returns (uint, uint) {
    Aggregator memory chainlinkAggregator = aggregators[feedId];
    if (address(chainlinkAggregator.aggregator) == address(0)) {
      revert SF_InvalidAggregator();
    }

    (uint80 roundId,
    int answer,,
    uint updatedAt,
    uint80 answeredInRound) = chainlinkAggregator.aggregator.latestRoundData();

    /* Chainlink carries over answer if consensus was not reached. 
     * Must get the timestamp of the actual round when answer was recorded */
    if (roundId == answeredInRound) {
      (roundId, , , updatedAt, ) = chainlinkAggregator.aggregator.latestRoundData();
    }

    /* Convert to correct decimals and uint*/
    uint spotPrice = DecimalMath.convertDecimals(
      SafeCast.toUint256(answer),
      chainlinkAggregator.decimals,
      18
    );

    return (spotPrice, updatedAt);
  }

  //////////////////
  // Adding feeds //
  //////////////////

  /**
   * @notice Assigns a chainlink aggregator and symbol to a given feedId
   * @param symbol bytes that returns the trading pair (e.g. "ETH/USDC")
   * @return feedId id set for a given trading pair
   */
  function addFeed(bytes32 symbol, address chainlinkAggregator, uint64 staleLimit) external returns (uint feedId) {
    feedId = ++lastFeedId;

    if (chainlinkAggregator == address(0)) {
      revert SF_InvalidAggregator();
    }

    if (staleLimit == 0) {
      revert SG_StaleLimitCannotBeZero();
    }

    /* store decimals once to reduce external calls during getSpotPrice */
    aggregators[feedId] = Aggregator({
      aggregator: AggregatorV3Interface(chainlinkAggregator),
      decimals: AggregatorV3Interface(chainlinkAggregator).decimals(),
      staleLimit: staleLimit
    });
    feedIdToSymbol[feedId] = symbol;
  }

  //////////
  // View //
  //////////

  /**
   * @notice Returns the trading pair symbol for a given feedId
   * @param feedId id of the feed
   * @return symbol bytes that returns the trading pair (e.g. "ETH/USDC")
   */
  function getSymbol(uint feedId) external view returns (bytes32 symbol) {
    return feedIdToSymbol[feedId];
  }

  ////////////
  // Errors //
  ////////////

  error SF_InvalidAggregator();

  error SG_StaleLimitCannotBeZero();

  error SF_SpotFeedStale(uint updatedAt, uint currentTime, uint staleLimit);

}