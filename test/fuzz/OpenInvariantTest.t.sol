// SPDX-License-Identifier: MIT
pragma solidity ~0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentalizedStableCoin.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openseppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvariants is StdInvariant, Test {
    DeployDecentralizedStableCoin deployer;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    DecentralizedStableCoin dsc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    function setUp() external {
        deployer = new DeployDecentralizedStableCoin();
        (dscEngine, dsc, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        // in open invariant test we just need to specify the target contract. nd foundry can go wild in the contract...
        
        targetContract(address(dscEngine));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalwbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 wethValue = dscEngine.getUsdvalue(weth, totalWethDeposited);
        uint256 btcValue = dscEngine.getUsdvalue(wbtc, totalwbtcDeposited);
        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", btcValue);
        console.log("totalSupply", totalSupply);

        assert(wethValue + btcValue >= totalSupply);
    }
}
