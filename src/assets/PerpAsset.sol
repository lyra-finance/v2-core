// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IPerpAsset} from "../interfaces/IPerpAsset.sol";
import {ISpotFeed} from "../interfaces/ISpotFeed.sol";
import {ISpotDiffFeed} from "../interfaces/ISpotDiffFeed.sol";
import {IAsset} from "../interfaces/IAsset.sol";

import {IManager} from "../interfaces/IManager.sol";

import {ManagerWhitelist} from "./utils/ManagerWhitelist.sol";

import {PositionTracking} from "./utils/PositionTracking.sol";
import {GlobalSubIdOITracking} from "./utils/GlobalSubIdOITracking.sol";

/**
 * @title PerpAsset
 * @author Lyra
 * @dev settlement refers to the action initiate by the manager that print / burn cash based on accounts' PNL and funding
 *      this contract keep track of users' pending funding and PNL, during trades
 *      and update them when settlement is called
 */
contract PerpAsset is IPerpAsset, PositionTracking, GlobalSubIdOITracking, ManagerWhitelist {
  using SafeERC20 for IERC20Metadata;
  using SignedMath for int;
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  /// @dev Max hourly funding rate
  int public maxRatePerHour;

  /// @dev Min hourly funding rate
  int public minRatePerHour;

  /// @dev Convergence period for funding rate in hours
  int public fundingConvergencePeriod = 8e18;

  ///////////////////////
  //  State Variables  //
  ///////////////////////

  /// @dev Spot feed, used to determine funding by comparing index to impactAsk or impactBid
  ISpotFeed public spotFeed;

  /// @dev Perp price feed, used for settling pnl before each trades
  ISpotDiffFeed public perpFeed;

  /// @dev Impact ask price feed, used for determining funding
  ISpotDiffFeed public impactAskPriceFeed;

  /// @dev Impact bid price feed, used for determining funding
  ISpotDiffFeed public impactBidPriceFeed;

  /// @dev Mapping from account to position
  mapping(uint accountId => PositionDetail) public positions;

  /// @dev Static hourly interest rate to borrow base asset, used to calculate funding
  int public staticInterestRate;

  /// @dev Latest aggregated funding that should be applied to 1 contract.
  int public aggregatedFunding;

  /// @dev Last time aggregated funding rate was updated
  uint public lastFundingPaidAt;

  /// @dev Flag to turn off the perp and allow migration
  bool public isDisabled;

  /// @dev Perp price at the time of disabling
  int public frozenPerpPrice;

  ///////////////////////
  //    Constructor    //
  ///////////////////////

  constructor(ISubAccounts _subAccounts) ManagerWhitelist(_subAccounts) {
    lastFundingPaidAt = block.timestamp;
  }

  //////////////////////////
  //  Owner Only Actions  //
  //////////////////////////

  /**
   * @notice Set new spot feed address
   * @param _spotFeed address of the new spot feed
   */
  function setSpotFeed(ISpotFeed _spotFeed) external onlyOwner {
    spotFeed = _spotFeed;

    emit SpotFeedUpdated(address(_spotFeed));
  }

  /**
   * @notice Set new perp feed address
   * @param _perpFeed address of the new perp feed
   */
  function setPerpFeed(ISpotDiffFeed _perpFeed) external onlyOwner {
    perpFeed = _perpFeed;

    emit PerpFeedUpdated(address(_perpFeed));
  }

  function setImpactFeeds(ISpotDiffFeed _impactAskPriceFeed, ISpotDiffFeed _impactBidPriceFeed) external onlyOwner {
    impactAskPriceFeed = _impactAskPriceFeed;
    impactBidPriceFeed = _impactBidPriceFeed;

    emit ImpactFeedsUpdated(address(_impactAskPriceFeed), address(_impactBidPriceFeed));
  }

  /**
   * @notice Set new static interest rate
   * @param _staticInterestRate New static interest rate for the asset.
   */
  function setStaticInterestRate(int _staticInterestRate) external onlyOwner {
    if (_staticInterestRate < -0.001e18 || _staticInterestRate > 0.001e18) revert PA_InvalidStaticInterestRate();
    staticInterestRate = _staticInterestRate;

    emit StaticUnderlyingInterestRateUpdated(_staticInterestRate);
  }

  /**
   * @notice Set new rate bounds
   */
  function setRateBounds(int _maxAbsRatePerHour) external onlyOwner {
    if (_maxAbsRatePerHour < 0) revert PA_InvalidRateBounds();
    maxRatePerHour = _maxAbsRatePerHour;
    minRatePerHour = -_maxAbsRatePerHour;

    emit RateBoundsUpdated(_maxAbsRatePerHour);
  }

  /**
   * @notice Set new funding convergence period
   */
  function setConvergencePeriod(uint _fundingConvergencePeriod) external onlyOwner {
    if (_fundingConvergencePeriod < 0.05e18 || _fundingConvergencePeriod > 240e18) revert PA_InvalidConvergencePeriod();
    fundingConvergencePeriod = _fundingConvergencePeriod.toInt256();

    emit ConvergencePeriodUpdated(fundingConvergencePeriod);
  }

  function disable() external onlyOwner {
    _updateFunding();
    // If frozen previously, this will just return itself
    frozenPerpPrice = _getPerpPrice();

    isDisabled = true;

    emit Disabled(frozenPerpPrice, aggregatedFunding);
  }

  ///////////////////////
  //   Account Hooks   //
  ///////////////////////

  /**
   * @notice This function is called by the Account contract whenever a PerpAsset balance is modified.
   * @dev    This function will close existing positions, and open new ones based on new entry price
   * @param adjustment Details about adjustment, containing account, subId, amount
   * @param preBalance Balance before adjustment
   * @param manager The manager contract that will verify the end state
   * @return finalBalance The final balance to be recorded in the account
   * @return needAllowance Return true if this adjustment should assume allowance in Account
   */
  function handleAdjustment(
    ISubAccounts.AssetAdjustment memory adjustment,
    uint tradeId,
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccounts returns (int finalBalance, bool needAllowance) {
    if (adjustment.subId != 0) revert PA_InvalidSubId();

    _checkManager(address(manager));

    // take snapshot and track total positions per manager, for caps
    _takeTotalPositionSnapshotPreTrade(manager, tradeId);
    _updateTotalPositions(manager, preBalance, adjustment.amount);

    // take snapshot and track global OI
    _takeSubIdOISnapshotPreTrade(adjustment.subId, tradeId);
    _updateSubIdOI(adjustment.subId, preBalance, adjustment.amount);

    // update last index price and settle unrealized pnl into position.pnl on the OLD balance
    _realizePNLWithMark(adjustment.acc, preBalance);

    // calculate funding from the last period, reflect changes in position.funding
    _updateFunding();
    _applyFundingOnAccount(adjustment.acc);

    return (preBalance + adjustment.amount, true);
  }

  ///////////////////////////
  //   Guarded Functions   //
  ///////////////////////////

  /**
   * @notice Manager-only function to clear pnl and funding before risk checks
   * @dev The manager should then update the cash balance of an account base on the returned values
   *      Only meaningful to call this function after a perp asset transfer, otherwise it will be 0.
   * @param accountId Account Id to settle
   */
  function settleRealizedPNLAndFunding(uint accountId)
    external
    onlyManagerForAccount(accountId)
    returns (int pnl, int funding)
  {
    return _clearRealizedPNL(accountId);
  }

  //////////////////////////
  //   Public Functions   //
  //////////////////////////

  /**
   * @notice Settle position with index, update lastIndex price and update position.PNL
   * @param accountId Account Id to settle
   */
  function realizeAccountPNL(uint accountId) external {
    _updateFunding();
    _applyFundingOnAccount(accountId);
    _realizePNLWithMark(accountId, _getPositionSize(accountId));
  }

  /**
   * @notice This function reflect how much cash should be mark "available" for an account
   * @dev The return WILL NOT be accurate if `_updateFunding` is not called in the same block
   *
   * @return totalCash is the sum of total funding, realized PNL and unrealized PNL
   */
  function getUnsettledAndUnrealizedCash(uint accountId) external view returns (int totalCash) {
    int size = _getPositionSize(accountId);
    int indexPrice = _getIndexPrice();
    int perpPrice = _getPerpPrice();

    int unrealizedFunding = _getUnrealizedFunding(accountId, size, indexPrice);
    int unrealizedPnl = _getUnrealizedPnl(accountId, size, perpPrice);
    return unrealizedFunding + unrealizedPnl + positions[accountId].funding + positions[accountId].pnl;
  }

  /**
   * @dev Return the hourly funding rate for an account
   */
  function getFundingRate() external view returns (int fundingRate) {
    if (isDisabled) {
      return 0;
    }
    int indexPrice = _getIndexPrice();
    fundingRate = _getFundingRate(indexPrice);
  }

  /**
   * @dev Return the current index price for the perp asset
   */
  function getIndexPrice() external view returns (uint, uint) {
    return spotFeed.getSpot();
  }

  /**
   * @dev Return the current mark price for the perp asset
   */
  function getPerpPrice() external view returns (uint, uint) {
    if (isDisabled) {
      return (uint(frozenPerpPrice), 1e18);
    }
    return perpFeed.getResult();
  }

  function getImpactPrices() external view returns (uint bid, uint ask) {
    (bid,) = impactBidPriceFeed.getResult();
    (ask,) = impactAskPriceFeed.getResult();
  }

  //////////////////////////
  //  Internal Functions  //
  //////////////////////////

  /**
   * @notice real perp position pnl based on current market price
   * @dev This function will update position.PNL, but not initiate any real payment in cash
   */
  function _realizePNLWithMark(uint accountId, int preBalance) internal {
    PositionDetail storage position = positions[accountId];

    int perpPrice = _getPerpPrice();
    int pnl = _getUnrealizedPnl(accountId, preBalance, perpPrice);

    position.lastMarkPrice = uint(perpPrice);
    position.pnl += pnl;

    emit PositionSettled(accountId, pnl, position.pnl, uint(perpPrice));
  }

  /**
   * @notice return pnl and funding kept in position storage and clear storage
   */
  function _clearRealizedPNL(uint accountId) internal returns (int pnl, int funding) {
    _updateFunding();
    _applyFundingOnAccount(accountId);

    PositionDetail storage position = positions[accountId];
    pnl = position.pnl;
    funding = position.funding;

    position.funding = 0;
    position.pnl = 0;

    int positionSize = _getPositionSize(accountId);

    if (isDisabled && positionSize != 0) {
      // If the perp has been disabled/migration enabled delete the position after realising PNL/funding
      subAccounts.assetAdjustment(
        ISubAccounts.AssetAdjustment({
          acc: accountId,
          asset: IAsset(address(this)),
          subId: 0,
          amount: -positionSize,
          assetData: bytes32(0)
        }),
        false,
        ""
      );
    }

    emit PositionCleared(accountId);
  }

  /**
   * @notice Apply the funding into positions[accountId].funding
   * @dev This should be called after `_updateFunding`
   *
   * Funding per Hour = (-1) × S × P × R
   * Where:
   *
   * S is the size of the position (positive if long, negative if short)
   * P is the oracle (index) price for the market
   * R is the funding rate (as a 1-hour rate)
   *
   * @param accountId Account Id to apply funding
   */
  function _applyFundingOnAccount(uint accountId) internal {
    int size = _getPositionSize(accountId);

    int funding = _getFunding(aggregatedFunding, positions[accountId].lastAggregatedFunding, size);
    // apply funding
    positions[accountId].funding += funding;
    positions[accountId].lastAggregatedFunding = aggregatedFunding;

    emit FundingAppliedOnAccount(accountId, funding, aggregatedFunding);
  }

  /**
   * @dev Update global funding, reflected on aggregatedFunding
   */
  function _updateFunding() internal {
    if (block.timestamp == lastFundingPaidAt || isDisabled) return;

    int indexPrice = _getIndexPrice();
    int fundingRate = _getFundingRate(indexPrice);
    int timeElapsed = (block.timestamp - lastFundingPaidAt).toInt256();

    aggregatedFunding += (fundingRate * timeElapsed / 1 hours).multiplyDecimal(indexPrice);
    lastFundingPaidAt = block.timestamp;

    emit AggregatedFundingUpdated(aggregatedFunding, fundingRate, lastFundingPaidAt);
  }

  /**
   * @dev return the hourly funding rate
   */
  function _getFundingRate(int indexPrice) internal view returns (int fundingRate) {
    int premium = _getPremium(indexPrice);
    fundingRate = premium.divideDecimalRound(fundingConvergencePeriod) + staticInterestRate;

    // capped at max / min
    if (fundingRate > maxRatePerHour) {
      fundingRate = maxRatePerHour;
    } else if (fundingRate < minRatePerHour) {
      fundingRate = minRatePerHour;
    }
  }

  /**
   * @dev get premium to calculate funding rate
   * Premium = (Max(0, Impact Bid Price - Index Price) - Max(0, Index Price - Impact Ask Price)) / Index Price
   */
  function _getPremium(int indexPrice) internal view returns (int premium) {
    (uint impactAskPrice,) = impactAskPriceFeed.getResult();
    (uint impactBidPrice,) = impactBidPriceFeed.getResult();

    if (impactAskPrice < impactBidPrice) revert PA_InvalidImpactPrices();

    int bidDiff = SignedMath.max(impactBidPrice.toInt256() - indexPrice, 0);
    int askDiff = SignedMath.max(indexPrice - impactAskPrice.toInt256(), 0);

    premium = (bidDiff - askDiff).divideDecimal(indexPrice);
  }

  /**
   * @dev Get unrealized funding if applyFunding is called now
   */
  function _getUnrealizedFunding(uint accountId, int size, int indexPrice) internal view returns (int funding) {
    PositionDetail storage position = positions[accountId];

    if (isDisabled) {
      return _getFunding(aggregatedFunding, position.lastAggregatedFunding, size);
    }

    int fundingRate = _getFundingRate(indexPrice);

    int timeElapsed = (block.timestamp - lastFundingPaidAt).toInt256();

    int latestAggregatedFunding = aggregatedFunding + (fundingRate * timeElapsed / 1 hours).multiplyDecimal(indexPrice);

    return _getFunding(latestAggregatedFunding, position.lastAggregatedFunding, size);
  }

  /**
   * @dev Get the exact funding amount by aggregated funding and size
   */
  function _getFunding(int globalAggregatedFunding, int lastAggregatedFunding, int size)
    internal
    pure
    returns (int funding)
  {
    int rateToPay = globalAggregatedFunding - lastAggregatedFunding;

    funding = -size.multiplyDecimal(rateToPay);
  }

  /**
   * @dev Get unrealized PNL if the position is closed at the current spot price
   */
  function _getUnrealizedPnl(uint accountId, int size, int perpPrice) internal view returns (int) {
    int lastMarkPrice = uint(positions[accountId].lastMarkPrice).toInt256();

    return (perpPrice - lastMarkPrice).multiplyDecimal(size);
  }

  /**
   * @dev Get number of contracts open, with 18 decimals
   */
  function _getPositionSize(uint accountId) internal view returns (int) {
    return subAccounts.getBalance(accountId, IPerpAsset(address(this)), 0);
  }

  function _getIndexPrice() internal view returns (int) {
    if (isDisabled) {
      // Note: this value should not get used anywhere when disabled, but must be left in for
      // certain function parameters
      return 0;
    }
    (uint spotPrice,) = spotFeed.getSpot();
    return spotPrice.toInt256();
  }

  function _getPerpPrice() internal view returns (int) {
    if (isDisabled) {
      return frozenPerpPrice;
    }
    (uint perpPrice,) = perpFeed.getResult();
    return perpPrice.toInt256();
  }

  //////////////////////////
  //      Modifiers       //
  //////////////////////////

  modifier onlyManagerForAccount(uint accountId) {
    if (msg.sender != address(subAccounts.manager(accountId))) revert PA_WrongManager();
    _;
  }
}
