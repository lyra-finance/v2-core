// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";

/**
 * @title ArrayLib
 * @author Lyra
 * @notice util functions for converting decimals
 */
library DecimalMath {
  /**
   * @dev convert amount based on decimals
   * @param amount amount in fromDecimals
   * @param fromDecimals original decimals
   * @param toDecimals target decimals
   */
  function convertDecimals(uint amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint) {
    if (fromDecimals == toDecimals) return amount;
    unchecked {
      // scale down
      if (fromDecimals > toDecimals) return amount / (10 ** (fromDecimals - toDecimals));
      // scale up
      else return amount * (10 ** (toDecimals - fromDecimals));
    }
  }
}
