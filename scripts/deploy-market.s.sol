// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {Option} from "../src/assets/Option.sol";
import {PerpAsset} from "../src/assets/PerpAsset.sol";
import {WrappedERC20Asset} from "../src/assets/WrappedERC20Asset.sol";
import {LyraSpotFeed} from "../src/feeds/LyraSpotFeed.sol";
import {LyraSpotDiffFeed} from "../src/feeds/LyraSpotDiffFeed.sol";
import {LyraVolFeed} from "../src/feeds/LyraVolFeed.sol";
import {LyraRateFeed} from "../src/feeds/LyraRateFeed.sol";
import {LyraForwardFeed} from "../src/feeds/LyraForwardFeed.sol";
import {OptionPricing} from "../src/feeds/OptionPricing.sol";
import {PMRM} from "../src/risk-managers/PMRM.sol";
import {PMRMLib} from "../src/risk-managers/PMRMLib.sol";
import {BasePortfolioViewer} from "../src/risk-managers/BasePortfolioViewer.sol";
import {IPMRM} from "../src/interfaces/IPMRM.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import "forge-std/console2.sol";
import {Deployment, ConfigJson, Market} from "./types.sol";
import {Utils} from "./utils.sol";

// get all default params
import "./config.sol";


/**
 * MARKET_NAME=weth forge script scripts/deploy-market.s.sol --private-key {} --rpc {} --broadcast
 **/
contract DeployMarket is Utils {

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);

    // revert if not found
    string memory marketName = vm.envString("MARKET_NAME");

    console2.log("Start deploying new market: ", marketName);
    address deployer = vm.addr(deployerPrivateKey);
    console2.log("Deployer: ", deployer);

    // load configs
    ConfigJson memory config = _loadConfig();

    // load deployed core contracts
    Deployment memory deployment = _loadDeployment();

    // deploy core contracts
    Market memory market = _deployMarketContracts(marketName, config, deployment);

    _setPermissionAndCaps(deployment, market);

    _setupPMRMParams(market);

    _registerMarketToSRM(deployment, market);

    _writeToMarketJson(marketName, market);

    vm.stopBroadcast();
  }


  /// @dev deploy all contract needed for a single market
  function _deployMarketContracts(string memory marketName, ConfigJson memory config, Deployment memory deployment) internal returns (Market memory market)  {
    // get the market ERC20 from config (it should be added to the config)
    address marketERC20 = _getMarketERC20(marketName, config);

    console2.log("target erc20:", marketERC20);

    //todo: use mocked feeds?

    market.spotFeed = new LyraSpotFeed();
    market.forwardFeed = new LyraForwardFeed(market.spotFeed);

    market.option = new Option(deployment.subAccounts, address(market.forwardFeed));

    market.perp = new PerpAsset(deployment.subAccounts, MAX_Abs_Rate_Per_Hour);

    market.base = new WrappedERC20Asset(deployment.subAccounts, IERC20Metadata(marketERC20));

    // feeds for perp
    market.perpFeed = new LyraSpotDiffFeed(market.spotFeed);
    market.iapFeed = new LyraSpotDiffFeed(market.spotFeed);
    market.ibpFeed = new LyraSpotDiffFeed(market.spotFeed);

    // interest and vol feed
    market.rateFeed = new LyraRateFeed();
    market.volFeed = new LyraVolFeed();

    market.spotFeed.setHeartbeat(SPOT_HEARTBEAT);
    market.perpFeed.setHeartbeat(PERP_HEARTBEAT);

    market.iapFeed.setHeartbeat(IMPACT_PRICE_HEARTBEAT);
    market.ibpFeed.setHeartbeat(IMPACT_PRICE_HEARTBEAT);

    market.volFeed.setHeartbeat(VOL_HEARTBEAT);
    market.rateFeed.setHeartbeat(RATE_HEARTBEAT);
    market.forwardFeed.setHeartbeat(FORWARD_HEARTBEAT);
    market.forwardFeed.setSettlementHeartbeat(SETTLEMENT_HEARTBEAT); 

    market.pricing = new OptionPricing();

    IPMRM.Feeds memory feeds = IPMRM.Feeds({
      spotFeed: market.spotFeed,
      stableFeed: deployment.stableFeed,
      forwardFeed: market.forwardFeed,
      interestRateFeed: market.rateFeed,
      volFeed: market.volFeed,
      settlementFeed: market.forwardFeed
    });

    market.pmrmLib = new PMRMLib(market.pricing);
    market.pmrmViewer = new BasePortfolioViewer(deployment.subAccounts, deployment.cash);

    market.pmrm = new PMRM(
      deployment.subAccounts, 
      deployment.cash, 
      market.option, 
      market.perp, 
      market.base, 
      deployment.auction,
      feeds,
      market.pmrmViewer,
      market.pmrmLib
    );
  }

  function _setupPMRMParams(Market memory market) internal {
    // set PMRM parameters
    (
      IPMRMLib.BasisContingencyParameters memory basisContParams,
      IPMRMLib.OtherContingencyParameters memory otherContParams,
      IPMRMLib.MarginParameters memory marginParams,
      IPMRMLib.VolShockParameters memory volShockParams
    ) = getPMRMParams();
    market.pmrmLib.setBasisContingencyParams(basisContParams);
    market.pmrmLib.setOtherContingencyParams(otherContParams);
    market.pmrmLib.setMarginParams(marginParams);
    market.pmrmLib.setVolShockParams(volShockParams);

    // set all scenarios!
    market.pmrm.setScenarios(getDefaultScenarios());
  }

  function _setPermissionAndCaps(Deployment memory deployment, Market memory market) internal {
    // each asset whitelist the newly deployed PMRM
    _whitelistAndSetCapForManager(address(market.pmrm), market);
    // each asset whitelist the standard manager
    _whitelistAndSetCapForManager(address(deployment.srm), market);
    console2.log("All asset whitelist both managers!");
  }

  function _registerMarketToSRM(Deployment memory deployment, Market memory market) internal {
    // find market ID
    uint8 marketId = 1;
    for (; marketId < 10; marketId++) {
      (int maxSpotReq,,,,,,,) = deployment.srm.optionMarginParams(marketId);
      if (maxSpotReq == 0) break;
    }
    console2.log("market ID for newly created market:", marketId);

    deployment.srm.setPricingModule(marketId, market.pricing);

    // set assets per market
    deployment.srm.whitelistAsset(market.perp, marketId, IStandardManager.AssetType.Perpetual);
    deployment.srm.whitelistAsset(market.option, marketId, IStandardManager.AssetType.Option);
    deployment.srm.whitelistAsset(market.base, marketId, IStandardManager.AssetType.Base);

    // set oracles
    deployment.srm.setOraclesForMarket(marketId, market.spotFeed, market.forwardFeed, market.volFeed);

    // set params
    deployment.srm.setOptionMarginParams(marketId, getDefaultSRMOptionParam());

    deployment.srm.setOracleContingencyParams(marketId, getDefaultSRMOracleContingency());

    (uint mmReq, uint imReq) = getDefaultSRMPerpRequirements();
    deployment.srm.setPerpMarginRequirements(marketId, mmReq, imReq);
  }

  function _whitelistAndSetCapForManager(address manager, Market memory market) internal {
    market.option.setWhitelistManager(manager, true);
    market.base.setWhitelistManager(manager, true);
    market.perp.setWhitelistManager(manager, true);

    market.option.setTotalPositionCap(IManager(manager), INIT_CAP_OPTION);
    market.perp.setTotalPositionCap(IManager(manager), INIT_CAP_PERP);
    market.base.setTotalPositionCap(IManager(manager), INIT_CAP_BASE);
  }

  /**
   * @dev write to deployments/{network}/{marketName}.json
   */
  function _writeToMarketJson(string memory name, Market memory market) internal {

    string memory objKey = "market-deployments";

    vm.serializeAddress(objKey, "option", address(market.option));
    vm.serializeAddress(objKey, "perp", address(market.perp));
    vm.serializeAddress(objKey, "base", address(market.base));
    vm.serializeAddress(objKey, "spotFeed", address(market.spotFeed));
    vm.serializeAddress(objKey, "perpFeed", address(market.perpFeed));
    vm.serializeAddress(objKey, "iapFeed", address(market.iapFeed));
    vm.serializeAddress(objKey, "ibpFeed", address(market.ibpFeed));
    vm.serializeAddress(objKey, "volFeed", address(market.volFeed));
    vm.serializeAddress(objKey, "rateFeed", address(market.rateFeed));
    vm.serializeAddress(objKey, "forwardFeed", address(market.forwardFeed));
    vm.serializeAddress(objKey, "pricing", address(market.pricing));
    vm.serializeAddress(objKey, "pmrm", address(market.pmrm));
    vm.serializeAddress(objKey, "pmrmLib", address(market.pmrmLib));
    string memory finalObj = vm.serializeAddress(objKey, "pmrmViewer", address(market.pmrmViewer));

    // build path
    _writeToDeployments(name, finalObj);
  }

}