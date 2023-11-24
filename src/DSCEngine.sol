//  SPDX-License-Identifier: MIT

pragma solidity ~0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./library/OracleLib.sol";
/**
 * @title Dsc Engine
 * @author Mayowa Abikoye
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAdressMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DscEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MIntFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotIMproved();

    using OracleLib for AggregatorV3Interface;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // means a 10% bonus;
    mapping(address token => address priceFeed) private s_priceFeed;
    mapping(address user => mapping(address token => uint256 tokenAmount)) private s_collateralDeposited;
    mapping(address user => uint256 dscMinted) private s_DscMinted;
    address[] private s_colaateralTokens;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );
    event change(uint256 indexed data);

    DecentralizedStableCoin private immutable i_dscAddress;

    modifier moreThanZero(uint256 _amountCollateral) {
        if (_amountCollateral <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeed[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAdressMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeed[tokenAddress[i]] = priceFeedAddress[i];
            s_colaateralTokens.push(tokenAddress[i]);
        }
        i_dscAddress = DecentralizedStableCoin(dscAddress);
    }

    /**
     *
     * @param tokenCollateralAddress the address of the token to be deposited as collateral
     * @param amountCollateral the amount of the token to be deposited as collateral
     * @param amountDscToMint the amount of the token to be minted as collateral
     * @notice this function wilm deposit your collateral and mint dsc in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
    /**
     * @param _tokenCollateralAddress the address of the token to deposit as collateral
     * @param _amountCollateral the amount of token to deposit..
     */

    function depositCollateral(address _tokenCollateralAddress, uint256 _amountCollateral)
        public
        moreThanZero(_amountCollateral)
        isAllowedToken(_tokenCollateralAddress)
        nonReentrant
    {
        address user = msg.sender;
        s_collateralDeposited[msg.sender][_tokenCollateralAddress] += _amountCollateral;
        emit CollateralDeposited(msg.sender, _tokenCollateralAddress, _amountCollateral);
        bool success = IERC20(_tokenCollateralAddress).transferFrom(user, address(this), _amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    /**
     *
     * @param tokenCollateralAddress the collateral Address to redeem
     * @param amountCollateral  the colllateral amount to redeem
     * notice this funtionburns and rededemsunderlying collateral in one transaction
     */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral) external {
        burnDsc(amountCollateral);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealhFatorIsBroken(msg.sender);
    }

    /**
     * @param _amountOfDscToMint the amount of stable coin to mint.
     * @notice they must have more collateral value than the minimum threshold..
     */
    function mintDsc(uint256 _amountOfDscToMint) public moreThanZero(_amountOfDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += _amountOfDscToMint;
        _revertIfHealhFatorIsBroken(msg.sender);
        bool minted = i_dscAddress.mint(msg.sender, _amountOfDscToMint);
        // may never get here...
        if (!minted) {
            revert DSCEngine__MIntFailed();
        }
    }

    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) {
        address sender = msg.sender;
        _burnDsc(amountDscToBurn, msg.sender, sender);
        _revertIfHealhFatorIsBroken(msg.sender);
    }

    /**
     * @param collateral the collateral to Liquidate
     * @param user the user to liquidate
     * @param deptToCover the amount of dsc you want to burn to imporve the users health factor...
     * @notice you can partially liquidatea user.
     * @notice you will  get aliquidation bonus for taking the users funds...
     * @notice this function only works assumes the protocol will be roughly200% overcollateralized in order for this to work...
     * @notice a Known bug would be that if the protocolwere 100% or less colateralized, then we woudlnt be able to incentivize the liquidators.
     * for example if the price of the collateral plummeted before any one can be liquidated...
     */
    function liquidate(address collateral, address user, uint256 deptToCover)
        external
        moreThanZero(deptToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountDebtCovered = getAmountFromUsd(collateral, deptToCover);
        // give a 10% incentive...
        uint256 bonusCollateral = (tokenAmountDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = bonusCollateral + tokenAmountDebtCovered;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(deptToCover, user, msg.sender);
        uint256 endingUSerHealthFacor = _healthFactor(user);
        if (endingUSerHealthFacor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotIMproved();
        }
        _revertIfHealhFatorIsBroken(msg.sender);
    }

    // internal and private functions...

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    /**
     * retuns how close to liquidation a user is
     * if a user goes below 1 then they can get liquidated...
     */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        (bool success) = i_dscAddress.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__MIntFailed();
        }
        i_dscAddress.burn(amountDscToBurn);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralValueUsd = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // to ensure that it retuns a uint.....
        if (totalDscMinted == 0) return type(uint256).max;
        return (collateralValueUsd * PRECISION / totalDscMinted);
    }

    function _revertIfHealhFatorIsBroken(address _user) internal view {
        uint256 userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DscEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        // solidity can perform a revert function if the balance is  negative
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        (bool success) = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_colaateralTokens.length; i++) {
            address token = s_colaateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdvalue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdvalue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount / PRECISION);
    }

    function getAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    // getter functions
    function getAccountInformation(address _tokenCollateralAddress) public view returns (uint256) {
        uint256 tokenAmount = s_collateralDeposited[msg.sender][_tokenCollateralAddress];
        return tokenAmount;
    }

    function getAccountInformation2(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValue)
    {
        (totalDscMinted, collateralValue) = _getAccountInformation(user);
    }

    function getAmountOfDscBurn(address user) public view returns (uint256) {
        return s_DscMinted[user];
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_colaateralTokens;
    }

    function getTokenPriceFeeds(address tokenCollateral) public view returns (address pricefeed) {
        pricefeed = s_priceFeed[tokenCollateral];
    }
}
