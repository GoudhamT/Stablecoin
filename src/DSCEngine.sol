//SPDX-License-Identifier:MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DecentralizedStableCoin} from "./DecentralizedStablecoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DSC Engine
 * @author Goudham T
 * @notice The system to be designed as minimal as possible and have token maintained 1 USD pegged= 1 token
 * This stablecoin has properties:
 *      Exogeneous collateral
 *      Dollar pegged
 *      Algorthmic stable
 * This DSC Engine always make sure, it is "overcollateralize" at no point, your DSC should never be below of your total value of collateral
 * It is similar to DAI if DAI had no governance, no fees and was backed by wETH and wBTC
 * @notice The contracts is the core of DSC system. It handles all logic for minting  and redeem DSC as well as depositing & withdraw collateral
 * @notice This contracts is loosely based on MakerDAO
 */
contract DSCEngine is ReentrancyGuard {
    /*Errors */
    error DSCEngine__AmountmustBeMoreThanZero();
    error DSCEngine__TokenAddressandPriceFeedAddressMustBeSameLength();
    error DSCEngine__TokenAddressNotFound();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsOK();
    error DSCEngine__HealthFactorNotImproved();

    /*State variables */
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; //means 10% bonus

    mapping(address tokenAddress => address priceFeed) private s_tokenPriceFeed;
    mapping(address sender => mapping(address tokenAddress => uint256 amount)) private s_collateralDeposited;
    mapping(address sender => uint256 mintedAmount) private s_DSCMinted;
    address[] private s_tokenAddresses;
    DecentralizedStableCoin private immutable i_dscAddress;

    /*Events */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemTo, address indexed toeknAddress, uint256 collateralAmount
    );
    /////////////////////////////////////////////
    ///              Modifiers                ///
    ////////////////////////////////////////////
    modifier validateAmount(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__AmountmustBeMoreThanZero();
        }
        _;
    }

    modifier validateTokenAddress(address _tokenAddress) {
        if (s_tokenPriceFeed[_tokenAddress] == address(0)) {
            revert DSCEngine__TokenAddressNotFound();
        }
        _;
    }

    /////////////////////////////////////////////
    ///              Functions                ///
    ////////////////////////////////////////////

    /*constructor */
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dsc) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressandPriceFeedAddressMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_tokenPriceFeed[tokenAddress[i]] = priceFeedAddress[i];
            s_tokenAddresses.push(tokenAddress[i]);
        }
        i_dscAddress = DecentralizedStableCoin(dsc);
    }

    /////////////////////////////////////////////
    ///          External Functions           ///
    ////////////////////////////////////////////
    /*
     *
     * @param tokenAddress - this is for to which token we are depositing collateral
     * @param collateralAmount  - this is for collateral amount to be deposited
     * @param amountToMint  - this is for amount to mint decentralized stablecoin
     * @notice : this function does both eposit collateral and mint DSC in single transaction
     */
    function depositCollateralAndMintDSC(address tokenAddress, uint256 collateralAmount, uint256 amountToMint)
        external
    {
        depositCollateral(tokenAddress, collateralAmount);
        mintDSC(amountToMint);
    }

    /*
     * @notice this follows CEI pattern
     * @param tokenAddress  - this represents ERC20 token address
     * @param amount - this is collateral amount to be deposited
     * nonReentrant is used to make sure, same sender cannot call deposit function until the previous is over
     */
    function depositCollateral(address tokenAddress, uint256 collateralAmount)
        public
        validateAmount(collateralAmount)
        validateTokenAddress(tokenAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenAddress, collateralAmount);
        bool transfer = IERC20(tokenAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!transfer) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice - this follows CEI pattern
     * @param amountToMint - This is amount to mint for our decentralized stablecoin
     */
    function mintDSC(uint256 amountToMint) public validateAmount(amountToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountToMint;
        // we have to make sure always collateral is more than DSC minted value by using threshold
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dscAddress.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function redeemCollateralForDSC(address tokenAddress, uint256 collateralAmount, uint256 amountToBurn) external {
        burnDSC(amountToBurn);
        redeemCollateral(tokenAddress, collateralAmount);
    }

    // in order to redeem collateral
    // 1. Health factor must be over 1 always, AFTER collateral pulled
    // Follows CEI - Check Effects, Interactions
    //normally all token transfer happens at last while redeem collatral we will transfer token first and check healthfactor
    // to avoid GAS fee
    function redeemCollateral(address tokenAddress, uint256 collateralAmount) public {
        _redeemCollateral(msg.sender, msg.sender, tokenAddress, collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDSC(uint256 amountDSC) public {
        _burnDSC(msg.sender, msg.sender, amountDSC);
        _revertIfHealthFactorIsBroken(msg.sender); // I don;t think this will hit
    }

    //if we do start nearing undercollaterzlization, we need someone to liquidate positions
    // $100 ETH backing $50 DSC
    // suddenly ETH price tanks down, now user has $20 worth ETH backing $50 DSC - which is not even 1 dollar

    // $75 backing $50 DSC
    // liquidator takes $75 bcking and burns $50 DSC

    /**
     *
     * @param collateral  - represents ERC20 collateral address
     * @param user  - person who broken healthfactor, their _healfactor should be alwats less than MIN_HEALTH_FACTOR
     * @param debtToCoverDSC  - the amount of DSC you want to burn to improve user's healthfactor
     * @notice you can partially liquidate a user
     * @notice user gets liquidation bonus for taking user funds
     * @notice this function works assumes protocol is 200% over collaterlized for this to work
     * @notice A known bug will be protocol is 100% or less collateralized, then we wonlt be incentive liquidators
     */
    function liquidate(address collateral, address user, uint256 debtToCoverDSC)
        external
        validateAmount(debtToCoverDSC)
        nonReentrant
    {
        //check user's healthfactor
        uint256 userBeforeHealthFactor = _healthFactor(user);
        if (userBeforeHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsOK();
        }
        // we want to burn "debt "DSC and take collateral
        // bad user: $140 ETH -> $100 DSC
        // debttocover = $100 DSC
        // nned to find $DSC == ?? ETH -> how much ETH
        uint256 tokenAountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCoverDSC);
        // give them 10% bonus
        // so we are giving %110 ETH for 100 DSC
        uint256 bonusCollateral = (tokenAountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeem = tokenAountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralRedeem);
        _burnDSC(user, msg.sender, debtToCoverDSC);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= userBeforeHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    /////////////////////////////////////////////
    ///    Private & Internal Functions      ///
    ////////////////////////////////////////////
    // check healthFacotr -> do they have enough collateral?
    // if not revert
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /**
     * @notice - checks healthFactor for person who calls it
     * @param user - calling user
     * @notice returns how close the liquidation is
     * if value goes below 1, then they can liquidate
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral VALUE
        (uint256 totalDSCMinted, uint256 totalCollateralValue) = _getAccountInformation(user);
        if (totalDSCMinted == 0) {
            return type(uint256).max;
        }
        // exmaple: liquidation = 50 which means 50%
        // if my collateral is 100 ETH then 50 DSC I can mint
        // when my threshold = 75 which is 75% then 75 / 100 = 0.75 => .75 * 100 = 75 DSC I can mint
        uint256 adjustedCollateralAmount = (totalCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (adjustedCollateralAmount * PRECISION) / totalDSCMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueinUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueinUSD = getAccountCollateralValue(user);
    }

    function _redeemCollateral(address from, address to, address tokenAddress, uint256 collateralAmount) private {
        s_collateralDeposited[from][tokenAddress] -= collateralAmount;
        emit CollateralRedeemed(from, to, tokenAddress, collateralAmount);
        bool success = IERC20(tokenAddress).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDSC(address onBehalfOf, address dscFrom, uint256 amountToBurn) private {
        s_DSCMinted[onBehalfOf] -= amountToBurn;
        bool success = i_dscAddress.transferFrom(dscFrom, address(this), amountToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dscAddress.burn(amountToBurn);
    }

    /////////////////////////////////////////////
    ///       Public & View Functions        ///
    ////////////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 collateralValueInUSD) {
        for (uint256 i = 0; i < s_tokenAddresses.length; i++) {
            address tokenAddress = s_tokenAddresses[i];
            uint256 collateralAmount = s_collateralDeposited[user][tokenAddress];
            collateralValueInUSD += getCollateralValueInUSD(tokenAddress, collateralAmount);
        }
        return collateralValueInUSD;
    }

    function getCollateralValueInUSD(address _token, uint256 _amount) public view returns (uint256) {
        address feedAddress = s_tokenPriceFeed[_token];
        uint256 adjustedPrice = getPriceFeedFromAddress(feedAddress);
        return (adjustedPrice * _amount) / PRECISION;
    }

    function getPriceFeedAddress(address _token) external view returns (address) {
        return s_tokenPriceFeed[_token];
    }

    function getTokenAmountFromUSD(address _token, uint256 _amountInWEI) public view returns (uint256) {
        address feedAddress = s_tokenPriceFeed[_token];
        uint256 adjustedPrice = getPriceFeedFromAddress(feedAddress);
        return adjustedPrice / _amountInWEI;
    }

    function getPriceFeedFromAddress(address _feedAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_feedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        uint256 adjustedPrice = uint256(price) * (10 ** (18 - decimals));
        return adjustedPrice;
    }

    function getCollateralAmount(address _token) external view returns (uint256) {
        return s_collateralDeposited[msg.sender][_token];
    }

    function getAccountInformation() external view returns (uint256 totalDSCMinted, uint256 collateralInUSD) {
        (totalDSCMinted, collateralInUSD) = _getAccountInformation(msg.sender);
        return (totalDSCMinted, collateralInUSD);
    }

    function maxMintableAmount(uint256 _collateralAmount) external pure returns (uint256) {
        return (_collateralAmount * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    }
}
