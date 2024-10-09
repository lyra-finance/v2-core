// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/console2.sol";

import {Utils} from "./utils.sol";

import {LyraERC20} from "../src/l2/LyraERC20.sol";


// Deploy mocked contracts: then write to script/input as input for deploying core and v2 markets
contract DeployERC20s is Utils {

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("Start deploying ERC20 contracts! deployer: ", deployer);

    address[] memory feedSigners = new address[](1);
    feedSigners[0] = deployer;

    // write to configs file: eg: input/31337/config.json
    string memory objKey = "network-config";
    vm.serializeAddress(objKey, "usdc", address(new LyraERC20("USDC", "USDC", 6)));
    // vm.serializeAddress(objKey, "btc", address(new LyraERC20("Lyra WBTC", "WBTC", 8)));
    // vm.serializeAddress(objKey, "eth", address(new LyraERC20("Lyra WETH", "WETH", 18)));
    // vm.serializeAddress(objKey, "usdt", address(new LyraERC20("Lyra USDT", "USDT", 6)));
    // vm.serializeAddress(objKey, "snx", address(new LyraERC20("Lyra SNX", "SNX", 18)));
    // vm.serializeAddress(objKey, "wsteth", address(new LyraERC20("Lyra x Lido wstETH", "wstETH", 18)));
//    vm.serializeAddress(objKey, "rsweth", address(new LyraERC20("Lyra rswETH", "wstETH", 18)));
//    vm.serializeAddress(objKey, "susde", address(new LyraERC20("Lyra Staked USDe", "sUSDe", 18)));

    vm.serializeAddress(objKey, "feedSigners", feedSigners);
    string memory finalObj = vm.serializeBool(objKey, "useMockedFeed", false);

    // build path
    // _writeToInput("config", finalObj);

    vm.stopBroadcast();
  }
}

// PRIVATE_KEY=0x136cfb508c086319f2cd5e7b3d60923c0b6ccee8bd8404fb4f5ed435980f1598 forge script scripts/deploy-erc20s.s.sol --private-key 0x136cfb508c086319f2cd5e7b3d60923c0b6ccee8bd8404fb4f5ed435980f1598 --rpc-url https://rpc-derive-fork-testnet-tsbukxq8bm.t.conduit.xyz --verify --verifier blockscout --verifier-url https://explorer-derive-fork-testnet-tsbukxq8bm.t.conduit.xyz/api  --broadcast --priority-gas-price 1
// PRIVATE_KEY=0x136cfb508c086319f2cd5e7b3d60923c0b6ccee8bd8404fb4f5ed435980f1598 forge script scripts/deploy-erc20s.s.sol --private-key 0x136cfb508c086319f2cd5e7b3d60923c0b6ccee8bd8404fb4f5ed435980f1598 --rpc-url https://rpc-derive-fork-mainnet-uwnjei7co0.t.conduit.xyz --verify --verifier blockscout --verifier-url https://explorer-derive-fork-mainnet-uwnjei7co0.t.conduit.xyz/api  --broadcast --priority-gas-price 1