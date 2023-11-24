// SPDX-License-Identifier: MIT

pragma solidity ~0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDecentralizedStableCoin is Script {
    DSCEngine dscEngine;
    DecentralizedStableCoin decentralizedStableCoin;
    address[] private tokenAddress;
    address[] private priceFeedAddress;

    function run() external returns (DSCEngine, DecentralizedStableCoin, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        tokenAddress = [weth, wbtc];
        priceFeedAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.deal(address(this), 1 ether);
        vm.startBroadcast(deployerKey);
        decentralizedStableCoin = new DecentralizedStableCoin(address(this));
        dscEngine = new DSCEngine(tokenAddress, priceFeedAddress, address(decentralizedStableCoin));
        vm.stopBroadcast();
        decentralizedStableCoin.transferOwnership(address(dscEngine));
        // vm.prank(address(dscEngine));
        // decentralizedStableCoin.mint(address(dscEngine), 2 ether);
        return (dscEngine, decentralizedStableCoin, helperConfig);
    }
}
