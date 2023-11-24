// SPDX-License-Identifier: MIT

pragma solidity ~0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockV3Aggregator} from "../test/mock/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getorCreateAnvilChain();
        }
    }

    uint8 public constant DECIMALS = 8;
    int256 public ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public default_anvil_key = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    function getorCreateAnvilChain() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeNetworkConfig.wbtcUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethUSdPriceFeed = new MockV3Aggregator(DECIMALS,ETH_USD_PRICE);
        MockV3Aggregator btcUSdPriceFeed = new MockV3Aggregator(DECIMALS,BTC_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("ethereum","eth");
        ERC20Mock wbtcMock = new ERC20Mock("Bitcoin","btc");

        vm.stopBroadcast();
        console.log("kkkkk");
        anvilNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUSdPriceFeed),
            wbtcUsdPriceFeed: address(btcUSdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: default_anvil_key
        });
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        console.log("here");
    }
}
