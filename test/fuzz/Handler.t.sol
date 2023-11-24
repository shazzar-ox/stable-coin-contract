// handles the way make function calls on Invariant Test. to prevent haphazard calls...abi

// SPDX-License-Identifier: MIT

pragma solidity ~0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openseppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mock/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    MockV3Aggregator public ethUsdPriceFeed;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintIscalled;
    address[] public usersWithCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        // now we want it to redeem collateral after deposit has been done
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        // dscEngine.getTokenPriceFeeds();

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getTokenPriceFeeds(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        console.log("see");
        // amountcollateral is too large so we need to control it
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }
    // helper function

    function mint(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValue) = dscEngine.getAccountInformation2(sender);
        console.log(collateralValue);
        int256 maxDscToMint = (int256(collateralValue) / 2) - int256(totalDscMinted);
        if (maxDscToMint == 0) {
            return;
        }
        timesMintIscalled++;
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
    }

        //  this breaks our test feed
    // function updateCollateral(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 userBalance = dscEngine.getAccountInformation(address(collateral));
        amountCollateral = bound(amountCollateral, 0, userBalance);
        if (amountCollateral == 0) {
            return;
        }
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
    }


    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
