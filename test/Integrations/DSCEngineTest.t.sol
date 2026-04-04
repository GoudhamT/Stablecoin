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
        uint256 collateralAmount = 1 ether;
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
        uint256 expectedDeposit = 1 ether;
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
}
