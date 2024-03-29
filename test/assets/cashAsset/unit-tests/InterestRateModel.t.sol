// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../../../../src/assets/InterestRateModel.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/ConvertDecimals.sol";

/**
 * @dev Simple testing for the InterestRateModel
 */
contract UNIT_InterestRateModel is Test {
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using DecimalMath for uint;

  InterestRateModel rateModel;

  function setUp() public {
    uint minRate = 0.06 * 1e18;
    uint rateMultiplier = 0.2 * 1e18;
    uint highRateMultiplier = 0.4 * 1e18;
    uint optimalUtil = 0.6 * 1e18;

    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);
  }

  function testLowUtilBorrowRate() public {
    uint supply = 10000;
    uint borrows = 5000;

    // Borrow rate should be 0.5 * 0.2 + 0.06 = 0.16
    uint lowRate = rateModel.getBorrowRate(supply, borrows);
    assertEq(lowRate, 0.16 * 1e18);
  }

  function testHighUtilBorrowRate() public {
    uint supply = 10000;
    uint borrows = 8000;

    // Borrow rate should be 0.5 * 0.2 + 0.06 = 0.16
    // normal rate = 0.6 * 0.2 + 0.06
    // higher rate = (0.8-0.6) * 0.4 + normal rate (0.18)
    //             = 0.26
    uint highRate = rateModel.getBorrowRate(supply, borrows);
    assertEq(highRate, 0.26 * 1e18);
  }

  function testNoBorrows() public {
    uint supply = 10000;
    uint borrows = 0;

    // Borrow rate should be minRate if util is 0
    uint rate = rateModel.getBorrowRate(supply, borrows);
    assertEq(rate, rateModel.minRate());
  }

  function testSimpleBorrowInterestFactor() public {
    uint time = 1 weeks;
    uint supply = 1000 ether;
    uint borrows = 500 ether;

    uint borrowRate = rateModel.getBorrowRate(supply, borrows);
    uint interestFactor = rateModel.getBorrowInterestFactor(time, borrowRate);

    // Should equal e^(time*borrowRate/365 days) - 1
    uint calculatedRate = 3073205794798734;

    assertEq(interestFactor, calculatedRate);
  }

  function testCannotBorrowInterestFactorTimeZero() public {
    uint time = 0;
    uint supply = 1000 ether;
    uint borrows = 500 ether;

    uint borrowRate = rateModel.getBorrowRate(supply, borrows);

    vm.expectRevert(abi.encodeWithSelector(IInterestRateModel.IRM_NoElapsedTime.selector, time));
    rateModel.getBorrowInterestFactor(time, borrowRate);
  }

  function testFuzzUtilizationRate(uint supply, uint borrows) public {
    vm.assume(supply <= 10000000000000000000000000000 ether);
    vm.assume(supply >= borrows);

    uint util = rateModel.getUtilRate(supply, borrows);

    if (borrows == 0) {
      assertEq(util, 0);
    } else {
      assertEq(util, borrows.divideDecimal(supply));
    }
  }

  function testFuzzUtilizationRateBounded(uint supply, uint borrows) public {
    vm.assume(supply < 10000000000000000000000000000 ether);
    vm.assume(borrows < 10000000000000000000000000000 ether);
    uint util = rateModel.getUtilRate(supply, borrows);
    assertLe(util, 1e18);
  }

  function testFuzzBorrowRate(uint supply, uint borrows) public {
    vm.assume(supply <= 10000000000000000000000000000 ether);
    vm.assume(supply >= borrows);

    uint util = rateModel.getUtilRate(supply, borrows);
    uint opUtil = rateModel.optimalUtil();
    uint minRate = rateModel.minRate();
    uint lowSlope = rateModel.rateMultiplier();
    uint borrowRate = rateModel.getBorrowRate(supply, borrows);

    if (util <= opUtil) {
      uint lowRate = util.multiplyDecimal(lowSlope) + minRate;
      assertEq(borrowRate, lowRate);
    } else {
      uint lowRate = opUtil.multiplyDecimal(lowSlope) + minRate;
      uint excessUtil = util - opUtil;
      uint highSlope = rateModel.highRateMultiplier();
      uint highRate = excessUtil.multiplyDecimal(highSlope) + lowRate;
      assertEq(borrowRate, highRate);
    }
  }

  function testFuzzBorrowInterestFactor(uint time, uint supply, uint borrows) public {
    vm.assume(supply <= 100000 ether);
    vm.assume(supply >= borrows);
    vm.assume(time > 0 && time <= block.timestamp + (365 days) * 100);

    uint borrowRate = rateModel.getBorrowRate(supply, borrows);
    uint interestFactor = rateModel.getBorrowInterestFactor(time, borrowRate);
    uint calculatedRate = FixedPointMathLib.exp((time * borrowRate / (365 days)).toInt256()) - ConvertDecimals.UNIT;

    assertEq(interestFactor, calculatedRate);
  }
}
