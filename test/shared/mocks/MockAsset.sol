// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import {IAsset} from "../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../src/interfaces/ISubAccounts.sol";
import {IManager} from "../../../src/interfaces/IManager.sol";

/**
 * @title MockAsset is the easiest Asset wrapper that wraps ERC20 into account system.
 * @dev   deployer can set MockAsset to not allow balance go negative.
 *        if set to "allowNegativeBalance = false", token must be deposited before using
 */
contract MockAsset is IAsset {
  using DecimalMath for uint;

  IERC20 token;
  ISubAccounts subAccounts;
  bool immutable allowNegativeBalance;

  // default: don't need positive allowance to increase someone's balance
  bool needPositiveAllowance = false;

  // default: need negative allowacen to subtract someone's balance
  bool needNegativeAllowance = true;

  // mocked state to test # of calls
  bool recordMangerChangeCalls;
  uint public handleManagerCalled;

  uint tokenToCashRate = 1e18;

  // mocked state to test reverting calls from bad manager
  mapping(address => bool) revertFromManager;

  constructor(IERC20 token_, ISubAccounts account_, bool allowNegativeBalance_) {
    token = token_;
    subAccounts = account_;
    allowNegativeBalance = allowNegativeBalance_;
  }

  function deposit(uint recipientAccount, uint subId, uint amount) external virtual {
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: subId,
        amount: int(amount.multiplyDecimal(tokenToCashRate)),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  // subid = 0
  function deposit(uint recipientAccount, uint amount) external virtual {
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amount.multiplyDecimal(tokenToCashRate)),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint accountId, uint amount, address recipientAccount) external virtual {
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: accountId,
        asset: IAsset(address(this)),
        subId: 0,
        amount: -int(amount.divideDecimal(tokenToCashRate)),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    token.transfer(recipientAccount, amount);
  }

  function handleAdjustment(
    ISubAccounts.AssetAdjustment memory adjustment,
    uint, /*tradeId*/
    int preBal,
    IManager _manager,
    address
  ) public view virtual returns (int finalBalance, bool needAllowance) {
    if (revertFromManager[address(_manager)]) revert();
    int result = preBal + adjustment.amount;
    if (result < 0 && !allowNegativeBalance) revert("negative balance");
    needAllowance = adjustment.amount > 0 ? needPositiveAllowance : needNegativeAllowance;
    return (result, needAllowance);
  }

  function setNeedPositiveAllowance(bool _needPositiveAllowance) external {
    needPositiveAllowance = _needPositiveAllowance;
  }

  function setNeedNegativeAllowance(bool _needNegativeAllowance) external {
    needNegativeAllowance = _needNegativeAllowance;
  }

  function setRevertAdjustmentFromManager(address _manager, bool _revert) external {
    revertFromManager[_manager] = _revert;
  }

  function setRecordManagerChangeCalls(bool _record) external {
    recordMangerChangeCalls = _record;
  }

  function setTokenToCashRate(uint rate) external {
    tokenToCashRate = rate;
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
