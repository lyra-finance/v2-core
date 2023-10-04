pragma solidity ^0.8.13;

import "../../shared/utils/JsonMechIO.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "../../../src/feeds/OptionPricing.sol";
import "../../shared/mocks/MockFeeds.sol";
/**
 * This is a shared util python generated test cases.
 * We hard coded certain expires
 */
abstract contract TestCaseExpiries {
  using stdJson for string;
  using SignedDecimalMath for int;

  JsonMechIO immutable jsonParser;
  OptionPricing immutable pricing;

  uint[8] expiries;

  mapping(string => uint) dateToExpiry;

  uint constant ethDefaultPrice = 2000e18;
  uint constant btcDefaultPrice = 28000e18;

  /// @notice the order is according to the alphabet order of JSON file
  struct Option {
    int amount;
    string expiry;
    uint strike;
    string typeOption;
    string underlying;
  }

  struct Base {
    int amount;
    string underlying;
  }

  struct Perp {
    int amount;
    int entryPrice;
    string underlying;
  }

  struct Result {
    int im;
    int mm;
  }

  struct TestCase {
    Base[] bases;
    int cash;
    Option[] options;
    Perp[] perps;
    Result result;
  }

  constructor() {
    jsonParser = new JsonMechIO();
    pricing = new OptionPricing();

    expiries[0] = block.timestamp + 3 days + 8 hours; //  2023 / 1 / 4
    expiries[1] = block.timestamp + 10 days + 8 hours; //  2023 / 1 / 11
    expiries[2] = block.timestamp + 17 days + 8 hours; //  2023 / 1 / 18
    expiries[3] = block.timestamp + 57 days + 8 hours; //  2023 / 2 / 27
    expiries[4] = block.timestamp + 215 days + 8 hours; // 2023 / 8 / 4
    expiries[5] = block.timestamp + 222 days + 8 hours; // 2023 / 8 / 11
    expiries[6] = block.timestamp + 229 days + 8 hours; // 2023 / 8 / 18
    expiries[7] = block.timestamp + 238 days + 8 hours; // 2023 / 8 / 25

    dateToExpiry["20230104"] = expiries[0];
    dateToExpiry["20230111"] = expiries[1];
    dateToExpiry["20230118"] = expiries[2];
    dateToExpiry["20230227"] = expiries[3];
    dateToExpiry["20230804"] = expiries[4];
    dateToExpiry["20230811"] = expiries[5];
    dateToExpiry["20230818"] = expiries[6];
    dateToExpiry["20230825"] = expiries[7];
  }


  function _setDefaultSpotAndForward() internal {
    uint conf = 1e18;

    MockFeeds ethFeeds = _ethFeeds();
    MockFeeds btcFeeds = _btcFeeds();

    ethFeeds.setSpot(ethDefaultPrice, conf);
    btcFeeds.setSpot(btcDefaultPrice, conf);

    // ethPerp.setMockPerpPrice(ethDefaultPrice + 1e18, conf); // $1 diff
    // btcPerp.setMockPerpPrice(btcDefaultPrice + 20e18, conf); // $20 diff

    // set all default expiries
    ethFeeds.setForwardPrice(expiries[0], ethDefaultPrice + 0.91e18, conf);
    ethFeeds.setForwardPrice(expiries[1], ethDefaultPrice + 2.83e18, conf);
    ethFeeds.setForwardPrice(expiries[2], ethDefaultPrice + 4.75e18, conf);
    ethFeeds.setForwardPrice(expiries[3], ethDefaultPrice + 15.76e18, conf);
    ethFeeds.setForwardPrice(expiries[4], ethDefaultPrice + 59e18, conf);
    ethFeeds.setForwardPrice(expiries[5], ethDefaultPrice + 61e18, conf);
    ethFeeds.setForwardPrice(expiries[6], ethDefaultPrice + 63e18, conf);
    ethFeeds.setForwardPrice(expiries[7], ethDefaultPrice + 66e18, conf);

    btcFeeds.setForwardPrice(expiries[0], btcDefaultPrice + 12.78e18, conf);
    btcFeeds.setForwardPrice(expiries[1], btcDefaultPrice + 39.66e18, conf);
    btcFeeds.setForwardPrice(expiries[2], btcDefaultPrice + 66.56e18, conf);
    btcFeeds.setForwardPrice(expiries[3], btcDefaultPrice + 220e18, conf);
    btcFeeds.setForwardPrice(expiries[4], btcDefaultPrice + 838e18, conf);
    btcFeeds.setForwardPrice(expiries[5], btcDefaultPrice + 865e18, conf);
    btcFeeds.setForwardPrice(expiries[6], btcDefaultPrice + 893e18, conf);
    btcFeeds.setForwardPrice(expiries[7], btcDefaultPrice + 929e18, conf);
  }

  function _ethFeeds() internal virtual returns (MockFeeds feed);

  function _btcFeeds() internal virtual returns (MockFeeds feed);

  
  function equal(string memory a, string memory b) internal pure returns (bool) {
    return keccak256(bytes(a)) == keccak256(bytes(b));
  }
}
