//SPDX-License-Identifier:MIT

// What are invarinats on this stablecoin?

// 1. Total number of DSC token minted should be always less than collateral deposited

// 2. Getter / viewer functions should not revert at any case

// 3. healthfactor should be always greater or equal to 1 -> this is not valid, why ? then there is no liquidation process needed

pragma solidity ^0.8.19;
import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantTest is StdInvariant, Test {
    // Collateral is grater than DSC total supply

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethToken;
    address btcToken;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, ethToken, btcToken,) = config.localNetworkConfig();
        targetContract(address(engine));
    }

    function invariant_checkTotalSupplyIsLesserThanCollateralDeposited() public {
        uint256 dscTotalSupply = dsc.totalSupply();
        uint256 wethTokenDeposited = IERC20(ethToken).balanceOf(address(engine));
        uint256 wbtcTokenDeposited = IERC20(btcToken).balanceOf(address(engine));
        uint256 ethTokenInUSDDeposited = engine.getCollateralValueInUSD(ethToken, wethTokenDeposited);
        uint256 btcTokenInUSDDeposited = engine.getCollateralValueInUSD(btcToken, wbtcTokenDeposited);
        console.log("supply is", dscTotalSupply);
        console.log("Eth in USD deposited", ethTokenInUSDDeposited);
        console.log("BTC in USD deposited", btcTokenInUSDDeposited);
        assert((ethTokenInUSDDeposited + btcTokenInUSDDeposited) >= dscTotalSupply);
    }
}
