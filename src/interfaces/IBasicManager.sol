// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IManager} from "src/interfaces/IManager.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";
import {IOption} from "src/interfaces/IOption.sol";

interface IBasicManager {
  enum AssetType {
    NotSet,
    Option,
    Perpetual
  }

  struct AssetDetail {
    bool isWhitelisted;
    AssetType assetType;
    uint8 marketId;
  }

  /**
   * @dev a basic manager portfolio contains up to 5 marketHoldings assets
   * each subAccount contains multiple derivative type
   */
  struct BasicManagerPortfolio {
    // @dev each subAccount take care of 1 base asset, for example ETH and BTC.
    MarketHolding[] marketHoldings;
    int cash;
  }

  struct MarketHolding {
    uint8 marketId;
    // perp position detail
    IPerpAsset perp;
    int perpPosition;
    // option position detail
    IOption option;
    ExpiryHolding[] expiryHoldings;
  }

  ///@dev contains portfolio struct for single expiry assets
  struct ExpiryHolding {
    /// expiry timestamp
    uint expiry;
    /// array of strike holding details
    Option[] options;
    /// sum of all call positions, used to determine if portfolio max loss is bounded
    int netCalls;
    /// temporary variable to count how many options is used
    uint numOptions;
  }

  struct Option {
    uint strike;
    int balance;
    bool isCall;
  }

  ///@dev Struct for Perp Margin Requirements
  struct PerpMarginRequirements {
    uint mmRequirement;
    uint imRequirement;
  }

  ///@dev Struct for Option Margin Parameters
  struct OptionMarginParameters {
    int scOffset1;
    int scOffset2;
    int mmSC;
  }

  ///////////////
  //   Errors  //
  ///////////////

  /// @dev Caller is not the Accounts contract
  error BM_NotAccounts();

  /// @dev Not whitelist manager
  error BM_NotWhitelistManager();

  /// @dev Not supported asset
  error BM_UnsupportedAsset();

  /// @dev Account is under water, need more cash
  error BM_PortfolioBelowMargin(uint accountId, int margin);

  /// @dev Invalid Parameters for perp margin requirements
  error BM_InvalidMarginRequirement();

  /// @dev Forward Price for an asset is 0
  error BM_NoForwardPrice();

  ///////////////////
  //    Events     //
  ///////////////////

  event AssetWhitelisted(address asset, uint8 marketId, AssetType assetType);

  event OraclesSet(uint8 marketId, address spotOracle, address forwardOracle, address settlementOracle);

  event PricingModuleSet(uint8 marketId, address pricingModule);

  event MarginRequirementsSet(uint8 marketId, uint perpMMRequirement, uint perpIMRequirement);

  event OptionMarginParametersSet(uint8 marketId, int scOffset1, int scOffset2, int mmSC);
}
