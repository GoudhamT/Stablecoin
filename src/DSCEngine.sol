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
contract DSCEngine {
    function depositCollateralAndMintDSC() external {}
    function depositCollateral() external{}
    function mintDSC() external {}
    function redeemCollateral() external {}
    function redeemCollaterla() external{}
    function burnDSC() external{}
    function liquidate() external{}
    fucntion getHealthFactor() external{}
}
