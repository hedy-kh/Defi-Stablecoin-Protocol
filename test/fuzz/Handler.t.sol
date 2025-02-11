// handler is what going to narrow down the way that we call function

/* fuzz testing is a way to test a function behavior using so many inputs
 there is two fuzz testing techinques ,
 1 .statless fuzz testing 
 2. state full fuzz testing 
  the state full fuzz testing is also referred as the invariant test

*/

// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployStableCoin} from "script/DeployStable.s.sol";
import {DecentralizedCoin} from "src/DecStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.t.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public numberTimeDSCFUNCalled = 1;
    address[] public usersCollateral;
    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;
        address[] memory collaterTokens = dsce.getTokenCollateral();
        weth = ERC20Mock(collaterTokens[0]);
        wbtc = ERC20Mock(collaterTokens[1]);
        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralseed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralseed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersCollateral.push(msg.sender);
    }
    // function updateCollateralPrice(uint96 newPrice) public {
    //   int256 NewPriceInt = int256(uint256(newPrice));
    //   ethUsdPriceFeed.updateAnswer(NewPriceInt);

    // }
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralDeposited(address(collateral), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        vm.assume(amountCollateral > 0);
        //vm.asume(amountCollateral>0); is skipping the case of amountCollateral ==0 it will skip function exuction
        //same as if (amountCollateral ==0){return;};
        dsce.redeemCollateral(address(collateral), amountCollateral);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        vm.assume(usersCollateral.length > 0);
        address sender = usersCollateral[addressSeed % usersCollateral.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInfo(sender);
        int256 maxdsc = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        vm.assume(maxdsc > 0);
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        amount = bound(amount, 0, uint256(maxdsc));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dsce.MintDsc(amount);
        vm.stopPrank();
        numberTimeDSCFUNCalled++;
    }
}
