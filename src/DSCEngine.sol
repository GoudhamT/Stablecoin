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

    /*State variables */
    mapping(address tokenAddress => address priceFedd) private s_tokenPriceFeed;
    mapping(address sender => mapping(address tokenAddress => uint256 amount)) private s_collateralDeposited;
    DecentralizedStableCoin private immutable i_dscAddress;

    /*Events */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
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
            s_tokenPriceFeed[tokenAddress[i] = priceFeedAddress[i]];
        }
        i_dscAddress = DecentralizedStableCoin(dsc);
    }
    function depositCollateralAndMintDSC() external {}

    function depositCollateral(address tokenAddress, uint256 amount)
        external
        validateAmount(amount)
        validateTokenAddress(tokenAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenAddress, amount);
        bool transfer = IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        if (!transfer) {
            revert DSCEngine__TransferFailed();
        }
    }

    function mintDSC() external {}
    function redeemCollateral() external {}
    function redeemCollaterla() external {}
    function burnDSC() external {}
    function liquidate() external {}
    function getHealthFactor() external {}
}
