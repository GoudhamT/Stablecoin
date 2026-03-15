//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;
import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../../test/Mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    uint256 private constant STARTING_DEPOSIT = 100 ether;
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
        ERC20Mock(ethToken).mint(USER, STARTING_DEPOSIT);
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
        uint256 deposit = 10 ether;
        // give USER some ETH token
        vm.startPrank(USER);
        // approve DSCEngine
        ERC20Mock(ethToken).approve(address(engine), deposit);
        uint256 approvedToken = ERC20Mock(ethToken).allowance(USER, address(engine));
        engine.depositCollateral(ethToken, deposit);
        vm.stopPrank();
        uint256 balanceUser = ERC20Mock(ethToken).balanceOf(USER);
        uint256 engineBalance = ERC20Mock(ethToken).balanceOf(address(engine));
        assertEq(balanceUser, 90 ether);
        assertEq(engineBalance, 10 ether);
    }
}
