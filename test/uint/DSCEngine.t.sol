// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DecentralizedCoin} from "src/DecStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployStableCoin} from "script/DeployStable.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TestDscEngine is Test {
    DeployStableCoin Deployer;
    DecentralizedCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public user = makeAddr("hedi");
    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    event CollateralRedeemed(
        address indexed redeemdFrom, address indexed Redeemto, address indexed token, uint256 amount
    );
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function setUp() public {
        Deployer = new DeployStableCoin();
        (dsc, dsce, config) = Deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(user, 10 ether);
    }

    address[] public tokenAddress;
    address[] public pricefeedAddresses;

    function testRevertIfTokenLenghtNotMatch() public {
        tokenAddress.push(weth);
        pricefeedAddresses.push(ethUsdPriceFeed);
        pricefeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSEN__MisMatchedLength.selector);
        new DSCEngine(tokenAddress, pricefeedAddresses, address(dsc));
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testDepositCollateralRevert() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        vm.expectRevert(DSCEngine.DSEN__zero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    // function testCollateralRedeemEvent() public {
    //     vm.startPrank(user);
    //     vm.deal(user, 10 ether);
    //     dsce.redeemCollateral(address(dsc), 1 ether);
    //     vm.expectEmit(true, true, true, false, address(this));
    //     vm.stopPrank();
    // }
    function testRevertWithUnapprovedCollateral() public {
        vm.startPrank(user);
        ERC20Mock RandomToken = new ERC20Mock("ran", "ran", user, 10 ether);
        vm.expectRevert(DSCEngine.DSEN_NotAllowedToken.selector);
        dsce.depositCollateral(address(RandomToken), 10 ether);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        dsce.depositCollateral(weth, 10 ether);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAcountInfo() public depositedCollateral {
        (uint256 totaldscMinted, uint256 collateralValueInusd) = dsce.getAccountInfo(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralInUsd = dsce.getTokenAmountFromUsd(weth, collateralValueInusd);
        assertEq(totaldscMinted, expectedTotalDscMinted);
        assertEq(10 ether, expectedCollateralInUsd);
    }

    function testDepositCollateralEvent() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        vm.expectEmit(true, true, true, false, address(dsce));
        emit CollateralDeposited(user, weth, 10 ether);
        dsce.depositCollateral(weth, 10 ether);
        vm.stopPrank();
    }

    function testDepositCollateralEventLogAndCollateralEquality() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        vm.recordLogs();
        dsce.depositCollateral(weth, 10 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory entries = logs[0]; // Access the first log

        assertEq(
            entries.topics[0], keccak256("CollateralDeposited(address,address,uint256)"), "Event signature mismatch!"
        );
        assertEq(address(uint160(uint256(entries.topics[1]))), user, "User mismatch!");
        assertEq(address(uint160(uint256(entries.topics[2]))), weth, "Token mismatch!");
        (uint256(entries.topics[3]), 10 ether, "Amount mismatch!");
        uint256 collateralDeposited = dsce.getCollateralDeposited(user, weth);
        assertEq(collateralDeposited, 10 ether, "Collateral deposit state mismatch");
        vm.stopPrank();
    }

    function testCalculateHealthFactorifZero() public {
        vm.startPrank(user);
        uint256 totalDscMinted = 0;
        uint256 collateralValueInUsd = 10 ether;
        uint256 healthFactor = dsce.getCalculateHealthFactor(totalDscMinted, collateralValueInUsd);
        assertEq(healthFactor, type(uint256).max);
        vm.stopPrank();
    }

    function testHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        uint256 totalDscMinted = 1000;
        uint256 collateralValueInUsd = 10 ether;
        uint256 collateralExpected = (collateralValueInUsd * 50) / 100;
        uint256 ExpectedReturn = (collateralExpected * 1e18) / totalDscMinted;
        uint256 RealHealthFactor = dsce.getCalculateHealthFactor(totalDscMinted, collateralValueInUsd);
        assertEq(ExpectedReturn, RealHealthFactor, "Health Factor calculation mismatch");
        uint256 getHealthFactor = dsce.getHealthFactor(user);
        //assertEq(getHealthFactor,RealHealthFactor,"Health Factor mismatch");
        vm.stopPrank();
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        address token = weth;
        uint256 amount = dsce.getCollateralDeposited(user, weth);
        //address[] public s_collateralTokens;
        dsce.addCollateralToken(weth);
        uint256 collateralValue = dsce.getAccountCollateralValue(user);
        assertEq(collateralValue, amount, "Collateral value mismatch");
    }

    function testCollateralEmitEvent() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        dsce.depositCollateral(weth, 10 ether);
        vm.expectEmit(true, true, true, true, address(dsce));
        emit CollateralRedeemed(user, user, weth, 10 ether);
        dsce.redeemCollateral(weth, 10 ether);
        vm.stopPrank();
    }

    function testBreakHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        uint256 expectedHealthFactor = 0;
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSEN__BreakHealthFactor.selector, expectedHealthFactor));
        dsce.MintDsc(1000);
        vm.stopPrank();
    }

    function testRevertHelathFactorOk() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), 10 ether);
        vm.deal(user, 20 ether);
        vm.expectRevert(DSCEngine.DSEN__HealthFactorOk.selector);
        dsce.liquidate(weth, user, 1);
        vm.stopPrank();
    }
}
