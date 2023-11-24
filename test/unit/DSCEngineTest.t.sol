// SPDX-License-Identifier: MIT

pragma solidity ~0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentalizedStableCoin.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openseppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mock/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDecentralizedStableCoin private deployDecentralizedStableCoin;
    DSCEngine private dscEngine;
    DecentralizedStableCoin private dscDecentralizedStableCoin;
    HelperConfig private helperConfig;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    uint256 userEthbalance = 2 ether;
    uint256 userBtcBalance = 3 ether;

    event CollateralDeposited(address indexed user, address indexed tokenCollateral, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed tokenAddress, uint256 amount);

    function setUp() external {
        deployDecentralizedStableCoin = new DeployDecentralizedStableCoin();
        (dscEngine, dscDecentralizedStableCoin, helperConfig) = deployDecentralizedStableCoin.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        // vm.prank(user);
        ERC20Mock(weth).mint(user, userEthbalance);
        // ERC20Mock(weth).mint(user2, userEthbalance);
        ERC20Mock(wbtc).mint(user, userBtcBalance);
        // console.log(ERC20Mock(weth).balanceOf(user), "ether");
        // console.log(ERC20Mock(wbtc).balanceOf(user), "btc");
    }

    // constructor test //_bound

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressAndPriceFeedAdressMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(deployDecentralizedStableCoin));
    }

    ////////////////////////////
    ////// price feed test/////
    ///////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), userEthbalance);
        // dscEngine.depositCollateralAndMintDsc(weth, 1 ether, 1000);
        dscEngine.depositCollateral(weth, userEthbalance);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMint() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), userEthbalance);
        dscEngine.depositCollateralAndMintDsc(weth, 1 ether, 1000);
        // dscEngine.depositCollateral(weth,userEthbalance);
        vm.stopPrank();
        _;
    }

    function testGetUsdValue() public {
        // vm.prank("user");
        uint256 ethAmount = 15 ether;
        uint256 expectedUSd = 30000 ether;
        uint256 price = dscEngine.getUsdvalue(weth, ethAmount);
        console.log(price);
        assertEq(price, expectedUSd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedweth = 0.05 ether;
        uint256 actualWeth = dscEngine.getAmountFromUsd(weth, usdAmount);
        assertEq(expectedweth, actualWeth);
    }

    function testRevertDepositColateralIsZero() public {
        vm.prank(user);
        (bool success) = ERC20Mock(weth).approve(user, 1000 ether);
        if (success) {
            vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
            dscEngine.depositCollateral(weth, 0);
        } else {
            console.log("faile");
        }
    }

    function testRevertIWithUnapprovedCollateral() public {
        ERC20Mock ranRoken = new ERC20Mock("ran", "ran");
        ERC20Mock(ranRoken).mint(user, userEthbalance);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dscEngine.depositCollateral(address(ranRoken), 3000);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public {
        vm.startPrank(user);
        console.log(ERC20Mock(weth).balanceOf(user));
        ERC20Mock(weth).approve(address(dscEngine), userEthbalance);
        emit CollateralDeposited(user, weth, userEthbalance);
        dscEngine.depositCollateral(weth, userEthbalance);
        uint256 tokenAmount = dscEngine.getAccountInformation(weth);
        assertEq(tokenAmount, userEthbalance);
        // () = dscEngine._getAccountInformation();
        vm.stopPrank();
    }

    function testDepositColateralRevertsWhenTransferFails() public {
        uint256 overBalance = 1 ether;
        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(dscEngine), userEthbalance);
        vm.expectRevert();
        dscEngine.depositCollateral(weth, overBalance);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo2() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValue) = dscEngine.getAccountInformation2(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dscEngine.getAmountFromUsd(weth, collateralValue);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(userEthbalance, expectedCollateralValueInUsd);
    }

    // test tredeem collateral function...
    function testRedeemCollateralRevertsIfCollateralIsZero() public depositedCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralEmitsAnEvent() public depositedCollateral {
        vm.prank(user);
        emit CollateralRedeemed(user, user, weth, userEthbalance);
        dscEngine.redeemCollateral(weth, userEthbalance);
        console.log(type(uint256).max);
    }

    function testRedeemCollateraDeductsCollateralFromInitialBalance() public depositedCollateral {
        vm.prank(user);
        dscEngine.redeemCollateral(weth, userEthbalance);
        uint256 tokenAmount = dscEngine.getAccountInformation(weth);
        assertEq(tokenAmount, 0);
    }

    function testReddemCollateralRevertsIfHealthFactorIsBroken() public depositedCollateralAndMint {
        vm.startPrank(user);

        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1000e8);
        // dscEngine.depositCollateralAndMintDsc(weth,2 ether,500);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DscEngine__BreaksHealthFactor.selector, 0));
        dscEngine.redeemCollateral(weth, 1 ether);
        vm.stopPrank();
    }

    function testMintDscRevertsIfAmountIsZero() public depositedCollateral {
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(1000e8);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }

    function testBurnDscRevertsIfAmountIsZero() public depositedCollateralAndMint {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDsc(0);
    }

    function testBurnDscChangesStateOfUSerBalance() public depositedCollateralAndMint {
        vm.startPrank(user);
        uint256 bal = dscEngine.getAmountOfDscBurn(user);
        console.log(bal);
        dscDecentralizedStableCoin.approve(address(dscEngine), userEthbalance);
        dscEngine.burnDsc(1000);
        uint256 userBalnce = dscDecentralizedStableCoin.balanceOf(user);
        assertEq(bal, userBalnce + 1000);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfTokenAmountIsZero() public depositedCollateralAndMint {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.liquidate(weth, user, 0);
    }

    function testLiquidateShouldRevertIfHealthFactorIsOkay() public depositedCollateralAndMint {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidate(weth, user, 1000);
    }

    function testLiquidateRevertsIfAnotherUserTriesToLiquidateUserAWithALowHealthFactor()
        public
        depositedCollateralAndMint
    {
        dscDecentralizedStableCoin.approve(address(dscEngine), 1 ether);
        vm.startPrank(user);
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(10e8);

        // vm.startPrank(user2);
        // ERC20Mock(weth).approve(address(dscEngine), userEthbalance);
        // dscEngine.depositCollateralAndMintDsc(weth, 1 ether, 1000);
        // // dscEngine.depositCollateral(weth,userEthbalance);
        // vm.stopPrank();
        vm.expectRevert();
        // vm.expectRevert(abi.encodeWithSelector(DSCEngine.DscEngine__BreaksHealthFactor.selector, 0));
        dscEngine.liquidate(weth, address(dscEngine), 1000 ether);
        vm.stopPrank();
    }
}
