// // SPDX-License-Identifier: SEE LICENSE IN LICENSE
// pragma solidity 0.8.20;

// import {Test,console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployStableCoin} from "script/DeployStable.s.sol";
// import {DecentralizedCoin} from "src/DecStableCoin.sol";
// import {DSCEngine} from "src/DSCEngine.sol";
// import {HelperConfig} from "script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract invariantTest is StdInvariant, Test {
//     DeployStableCoin deployer;
//     DSCEngine dsce;
//     DecentralizedCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;
//     address public user = makeAddr("hedi");

//     function setUp() external {
//         deployer = new DeployStableCoin();
//         (dsc, dsce, config) = deployer.run();
//         (,,weth,wbtc,)=config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }
//     function invariant_protocolMoreValueToSupply() public view{
//       uint256 totalSupply = dsc.totalSupply();
//       uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
//       uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
//       uint256 wethValue = dsce.getUsdValue(weth,totalWethDeposited);
//       uint256 wbtcValue = dsce.getUsdValue(wbtc,totalWbtcDeposited);
//       console.log("weth value :",wethValue);
//       console.log("wbtc value :",wbtcValue);
//       assert(wethValue + wbtcValue >= totalSupply);
//     }

// }
