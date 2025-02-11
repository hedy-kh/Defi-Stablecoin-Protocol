// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedCoin} from "src/DecStableCoin.sol";
import {Vm} from "forge-std/Vm.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TestDscCoin is Test {
    DecentralizedCoin dsc;
    address user = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        dsc = new DecentralizedCoin();
    }

    function testRevertIfAmountZero() public {
        uint256 amount = 0;
        vm.startPrank(user);
        vm.expectRevert(DecentralizedCoin.Dec__ZeroAmount.selector);
        dsc.burn(amount);
        vm.stopPrank();
    }

    function testRevertIfuserHasNoFunds() public {
        uint256 amount = 1000;
        vm.startPrank(user);
        vm.expectRevert(DecentralizedCoin.Dec__NoFunds.selector);
        dsc.burn(amount);
        vm.stopPrank();
    }

    function testRevertIfWrongAddress() public {
        uint256 amount = 1000;
        vm.startPrank(user);
        vm.expectRevert(DecentralizedCoin.Dec__wrongAddress.selector);
        dsc.mint(address(0), amount);
        vm.stopPrank();
    }

    function testRevertIfZeroAmountMint() public {
        uint256 amount = 0;
        vm.startPrank(user);
        vm.expectRevert(DecentralizedCoin.Dec__ZeroAmount.selector);
        dsc.mint(user, amount);
        vm.stopPrank();
    }

    function testMintFunction() public {
        uint256 amount = 1000;
        vm.startPrank(user);
        bool success = dsc.mint(user, amount);
        assertTrue(success);
        vm.stopPrank();
    }
}
