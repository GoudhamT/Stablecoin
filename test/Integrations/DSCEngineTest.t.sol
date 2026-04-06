//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "test/Mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig helperConfig;
    address ethPrice;
    address btcPrice;
    address ethToken;
    address btcToken;
    address USER;
    uint256 private STARTING_BALANCE = 100 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethPrice, btcPrice, ethToken, btcToken,) = helperConfig.localNetworkConfig();
        USER = makeAddr("user");
        vm.deal(USER, STARTING_BALANCE);
        ERC20Mock(ethToken).mint(USER, 20 ether);
        ERC20Mock(btcToken).mint(USER, 10 ether);
    }

    ///////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////Price Feed Cases//////////////////////////////////////
    ///////////////////////////////////////////////////////////////////////////////////

    function testComparePriceFeedData() public {
        uint256 expectedPrice = 2e21;
        uint256 actualPrice = engine.getPriceFeedFromAddress(ethPrice);
        assertEq(expectedPrice, actualPrice);
    }

    //////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////Constructor////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////
    address[] tokenAddress;
    address[] priceFeedAddress;

    function testTokenAndPriceAddressSameLength() public {
        tokenAddress.push(ethToken);
        priceFeedAddress.push(ethPrice);
        priceFeedAddress.push(ethPrice);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressandPriceFeedAddressMustBeSameLength.selector);
        DSCEngine tempEngine = new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
    }

    //////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////Deposit Collateral///////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////

    modifier depositCollateralAmount() {
        uint256 collateralAmount = 2 ether;
        vm.startPrank(USER);
        IERC20(ethToken).approve(address(engine), collateralAmount);
        engine.depositCollateral(ethToken, collateralAmount);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAmountZeroError() public {
        uint256 depositAmount = 0;
        vm.expectRevert(DSCEngine.DSCEngine__AmountmustBeMoreThanZero.selector);
        engine.depositCollateral(ethToken, depositAmount);
    }

    function testDepositCollateralInvalidAddress() public {
        uint256 depositAmount = 1 ether;
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressNotFound.selector);
        engine.depositCollateral(ethPrice, depositAmount);
    }

    function testDepositCollateral() public {
        uint256 collateralAmount = 1 ether;
        vm.startPrank(USER);
        IERC20(ethToken).approve(address(engine), collateralAmount);
        engine.depositCollateral(ethToken, collateralAmount);
        vm.stopPrank();
    }

    function testVerifyCollateralDeposited() public depositCollateralAmount {
        uint256 expectedDeposit = 2 ether;
        vm.prank(USER);
        uint256 actualDeposit = engine.getCollateralAmount(ethToken);
        assertEq(expectedDeposit, actualDeposit);
    }

    function testEmitCollateralDepositEvent() public {
        uint256 depositAmount = 2 ether;
        vm.startPrank(USER);
        IERC20(ethToken).approve(address(engine), 10 ether);
        vm.expectEmit(true, true, true, false, address(engine));
        emit CollateralDeposited(USER, ethToken, depositAmount);
        engine.depositCollateral(ethToken, depositAmount);
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////HealthFactor//////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////
    function testVerifyColleteralAmountInUSD() public depositCollateralAmount {
        uint256 expectedCollateralInUSD = 4000e18;
        vm.prank(USER);
        uint256 depositedCollateral = engine.getCollateralAmount(ethToken);
        uint256 actualCollateralInUSD = engine.getCollateralValueInUSD(ethToken, depositedCollateral);
        console.log("actual deposit", actualCollateralInUSD);
        assertEq(expectedCollateralInUSD, actualCollateralInUSD);
    }

    function testCompareUserCollateralValue() public depositCollateralAmount {
        uint256 expectedCollateralInUSD = 4000e18;
        // vm.startPrank(USER);
        uint256 actualCollateralDeposited = engine.getAccountCollateralValue(USER);
        // vm.stopPrank();
        assertEq(expectedCollateralInUSD, actualCollateralDeposited);
    }

    function testDepositAndValidateVariousToken() public depositCollateralAmount {
        uint256 depositBTCCollateral = 3 ether;
        uint256 expectedTotalCollateral = 7e21;
        vm.startPrank(USER);
        IERC20(btcToken).approve(address(engine), depositBTCCollateral);
        engine.depositCollateral(btcToken, depositBTCCollateral);
        uint256 actualTotalCollateral = engine.getAccountCollateralValue(USER);
        vm.stopPrank();
        assertEq(expectedTotalCollateral, actualTotalCollateral);
    }

    function testVerifyAccountInformation() public depositCollateralAmount {
        uint256 expectedCollateralInUSD = 4000e18;
        uint256 expectedDSCMinted = 0;
        vm.prank(USER);
        (uint256 actualDSCMinted, uint256 actualCollateralInUSD) = engine.getAccountInformation();
        assertEq(expectedCollateralInUSD, actualCollateralInUSD);
        assertEq(expectedDSCMinted, actualDSCMinted);
    }

    function testGetHealthFactor() public depositCollateralAmount {
        uint256 healthFactor = engine.getHealthFactor();
        assert(healthFactor > 1);
    }

    function testHealthFactorIsUint256MaxWhenNotMinted() public depositCollateralAmount {
        uint256 healthFactor = engine.getHealthFactor();
        uint256 maxNumber = type(uint256).max;
        assert(healthFactor == maxNumber);
    }

    function testHealthFactorIsOne() public depositCollateralAmount {
        // deposit value is 2 ether
        // ether values at 2000 USD so total collateral is 4000 USD
        uint256 mintingAmount = 2000e18;
        vm.startPrank(USER);
        engine.mintDSC(mintingAmount);
        uint256 userHealthFactor = engine.getHealthFactor();
        vm.stopPrank();
        assert(userHealthFactor == 1e18);
    }

    //////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////Minting////////////////////////////////////////
    //////////////////////////////////////////////////////////////////////////////////
    function testMintingWorkAfterDeposit() public depositCollateralAmount {
        uint256 mintToken = 2 ether;
        vm.prank(USER);
        engine.mintDSC(mintToken);
    }

    function testErrorMintingWithoutDepositing() public {
        uint256 mintToken = 2 ether;
        uint256 userHealthFactor = 0;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, userHealthFactor));
        engine.mintDSC(mintToken);
    }

    function testMintingBreaksHealthFactor() public depositCollateralAmount {
        vm.startPrank(USER);
        uint256 collateralInUSD = engine.getAccountCollateralValue(USER);
        uint256 maxMintable = engine.maxMintableAmount(collateralInUSD);
        uint256 mintingAmount = maxMintable + 1;
        // vm.expectRevert(DSCEngine.DSCEngine__BreaksHealthFactor.selector);
        vm.expectRevert();
        engine.mintDSC(mintingAmount);
        vm.stopPrank();
    }

    //////////////////////////////////////////////////////////////////////////////////
    ////////////////////Deposit Collateral and Mint together//////////////////////////
    //////////////////////////////////////////////////////////////////////////////////
    function testDepositAndMintWorks() public {
        vm.startPrank(USER);
        uint256 depositCollateral = 2 ether;
        uint256 mintDSC = 1 ether;
        IERC20(ethToken).approve(address(engine), depositCollateral);
        engine.depositCollateralAndMintDSC(ethToken, depositCollateral, mintDSC);
        vm.stopPrank();
    }

    function testDepositAndMintFails() public {
        uint256 depositCollateral = 2 ether;
        uint256 mintDSC = 3000 ether;
        vm.startPrank(USER);
        IERC20(ethToken).approve(address(engine), depositCollateral);
        vm.expectRevert();
        engine.depositCollateralAndMintDSC(ethToken, depositCollateral, mintDSC);
        vm.stopPrank();
    }
}
