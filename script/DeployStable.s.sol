// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {DecentralizedCoin} from "src/DecStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployStableCoin is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.startBroadcast(deployerKey);
        DecentralizedCoin stableCoin = new DecentralizedCoin();
        DSCEngine engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(stableCoin));
        stableCoin.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (stableCoin, engine, config);
    }
}
