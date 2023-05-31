// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract IPMRMLib {
  struct VolShockParameters {
    /// @dev The max vol shock, that can be scaled down
    uint volRangeUp;
    /// @dev The maxx
    uint volRangeDown;
    int shortTermPower;
    int longTermPower;
    uint dteFloor;
  }

  struct StaticDiscountParameters {
    uint rateMultiplicativeFactor;
    uint rateAdditiveFactor;
    uint baseStaticDiscount;
  }

  struct ForwardContingencyParameters {
    uint spotShock1;
    uint spotShock2;
    uint additiveFactor;
    uint multiplicativeFactor;
  }

  struct OtherContingencyParameters {
    /// @dev Below this threshold, we consider the stable asset de-pegged, so we add additional contingency
    uint pegLossThreshold;
    /// @dev If below the peg loss threshold, we add this contingency
    uint pegLossFactor;
    /// @dev Below this threshold, IM is affected by confidence contingency
    uint confidenceThreshold;
    /// @dev Percentage of spot used for confidence contingency, scales with the minimum contingency seen.
    uint confidenceFactor;
    /// @dev Contingency applied to base held in the portfolio, multiplied by spot.
    uint basePercent;
    /// @dev Contingency applied to perps held in the portfolio, multiplied by spot.
    uint perpPercent;
    /// @dev Factor for multiplying number of naked shorts (per strike) in the portfolio, multipled by spot.
    uint optionPercent;
  }

  ////////////
  // Errors //
  ////////////

  /// @dev emitted when provided forward contingency parameters are invalid
  error PMRML_InvalidForwardContingencyParameters();
  /// @dev emitted when provided other contingency parameters are invalid
  error PMRML_InvalidOtherContingencyParameters();
  /// @dev emitted when provided static discount parameters are invalid
  error PMRML_InvalidStaticDiscountParameters();
  /// @dev emitted when provided vol shock parameters are invalid
  error PMRML_InvalidVolShockParameters();
}