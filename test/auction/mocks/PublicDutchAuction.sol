// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../src/liquidation/DutchAuction.sol";

contract PublicDutchAuction is DutchAuction {
  constructor(ISubAccounts _subAccounts, ISecurityModule _securityModule, ICashAsset _cash)
    DutchAuction(_subAccounts, _securityModule, _cash)
  {}

  function getInsolventAuctionBidPrice(uint accountId, int maintenanceMargin, int markToMarket)
    public
    view
    returns (int)
  {
    return _getInsolventAuctionBidPrice(accountId, maintenanceMargin, markToMarket);
  }
}
