//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;
import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/Mocks/AggregatorV3Mock.sol";
import {ERC20Mock} from "test/Mocks/ERC20Mock.sol";

abstract contract codeConstant {
    uint256 public constant SEPOLIA_CHAIN = 11155111;
    uint8 public constant V3_DECIMALS = 8;
    int256 public constant ETH_V3_AMOUNT = 2000e8;
    int256 public constant BTC_V3_AMOUNT = 1000e8;
    uint256 public constant ETH_AMOUNT = 2000e8;
    uint256 public constant BTC_AMOUNT = 1000e8;
    string public constant ETH_TOKEN_NAME = "WETH";
    string public constant BTC_TOKEN_NAME = "WBTC";
    uint256 public constant ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
}

contract HelperConfig is Script, codeConstant {
    struct NetworkConfig {
        address ethPriceFeed;
        address btcPriceFeed;
        address wethToken;
        address wbtcToken;
        uint256 default_key;
    }
    NetworkConfig public localNetworkConfig;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN) {
            localNetworkConfig = getSepoliaConfig();
        } else {
            localNetworkConfig = getOrCreateConfig();
        }
    }

    function getSepoliaConfig() private view returns (NetworkConfig memory) {
        return NetworkConfig({
            ethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            btcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wethToken: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wbtcToken: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            default_key: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateConfig() private returns (NetworkConfig memory) {
        if (localNetworkConfig.ethPriceFeed != address(0)) {
            return localNetworkConfig;
        }
        // Deploy Mock
        vm.startBroadcast();
        MockV3Aggregator ETHPriceMock = new MockV3Aggregator(V3_DECIMALS, ETH_V3_AMOUNT);
        MockV3Aggregator BTCPriceMock = new MockV3Aggregator(V3_DECIMALS, BTC_V3_AMOUNT);
        ERC20Mock ETHTokenMock = new ERC20Mock(ETH_TOKEN_NAME, ETH_TOKEN_NAME, msg.sender, ETH_AMOUNT);
        ERC20Mock BTCTokenMock = new ERC20Mock(BTC_TOKEN_NAME, BTC_TOKEN_NAME, msg.sender, BTC_AMOUNT);
        vm.stopBroadcast();
        return NetworkConfig({
            ethPriceFeed: address(ETHPriceMock),
            btcPriceFeed: address(BTCPriceMock),
            wethToken: address(ETHTokenMock),
            wbtcToken: address(BTCTokenMock),
            default_key: ANVIL_KEY
        });
    }
}
