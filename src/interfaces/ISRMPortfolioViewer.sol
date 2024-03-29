// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IStandardManager} from "./IStandardManager.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";

import {IBasePortfolioViewer} from "../interfaces/IBasePortfolioViewer.sol";

/**
 * @title ISRMPortfolioViewer
 * @notice view function for Standard Manager
 * @author Lyra
 */
interface ISRMPortfolioViewer is IBasePortfolioViewer {
  function getSRMPortfolio(uint accountId) external view returns (IStandardManager.StandardManagerPortfolio memory);

  function arrangeSRMPortfolio(ISubAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IStandardManager.StandardManagerPortfolio memory);
}
