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

    /*State variables */
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address tokenAddress => address priceFeed) private s_tokenPriceFeed;
    mapping(address sender => mapping(address tokenAddress => uint256 amount)) private s_collateralDeposited;
    mapping(address sender => uint256 mintedAmount) private s_DSCMinted;
    address[] private s_tokenAddresses;
    DecentralizedStableCoin private immutable i_dscAddress;

    /*Events */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed toeknAddress , uint256 collateralAmount);
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
            _;
        }
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
    function redeemCollateralForDSC(address tokenAddress , uint256 collateralAmount, uint256 amountToBurn) external {
        burnDSC(amountToBurn);
        redeemCollateral(tokenAddress,collateralAmount);
    }
    // in order to redeem collateral
    // 1. Health factor must be over 1 always, AFTER collateral pulled 
    // Follows CEI - Check Effects, Interactions 
    //normally all token transfer happens at last while redeem collatral we will transfer token first and check healthfactor
    // to avoid GAS fee
    function redeemCollateral(address tokenAddress,uint256 collateralAmount) public {
        s_collateralDeposited[msg.sender][tokenAddress] -= collateralAmount;
        emit CollateralRedeemed(msg.sender,tokenAddress,collateralAmount);
        bool success = IERC20(tokenAddress).transfer(address(this), collateralAmount);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);

    }

    function burnDSC(uint256 amountDSC) public {
        s_DSCMinted[msg.sender] -= amountDSC;
        bool success = i_dscAddress.transferFrom(msg.sender, address(this), amountDSC)
        if (!success){
            revert DSCEngine__TransferFailed();
        }
        i_dscAddress.burn(amountDSC);
    }
    function liquidate() external {}
    function getHealthFactor() external {}

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
        // exmaple: luqiodation = 50 which means 50%
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
        AggregatorV3Interface priceFeed = AggregatorV3Interface(feedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        uint256 adjustedPrice = uint256(price) * (10 ** (18 - decimals));
        return (adjustedPrice * _amount) / PRECISION;
    }

    function getPriceFeedAddress(address _token) external view returns (address) {
        return s_tokenPriceFeed[_token];
    }
}
