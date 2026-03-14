//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;
import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test, IERC20 {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address ethPriceFeed;
    address ethToken;
    address public USER;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethPriceFeed,, ethToken,,) = config.localNetworkConfig();
        USER = makeAddr("user");
    }

    ///////////////////////////////////////
    /////////// Price Feed ///////////////
    /////////////////////////////////////
    function testValueInUSD() public {
        uint256 collateralAmount = 10 ether;
        uint256 expectedValueInUSD = 20000e18;
        address price = engine.getPriceFeedAddress(ethToken);
        uint256 resultValueInUSD = engine.getCollateralValueInUSD(ethToken, collateralAmount);
        assertEq(expectedValueInUSD, resultValueInUSD);
    }

    ///////////////////////////////////////
    ////////Deposit Collateral ///////////
    /////////////////////////////////////
    function testDepositZeroAmountError() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountmustBeMoreThanZero.selector);
        engine.depositCollateral(ethToken, 0);
    }

    function testErrorInvalidAddress() public {
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressNotFound.selector);
        engine.depositCollateral(USER, 100);
    }

    function testDepositCollateral() public {
        vm.prank(USER);
        engine.depositCollateral(ethToken, 10 ether);
        uint256 balance = balanceOf(address(this));
        assertEq(balance, 10e18);
    }
}
