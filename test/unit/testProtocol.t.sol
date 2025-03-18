//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployProtocol} from "../../script/Deployprotocol.s.sol";
import {Protocol} from "../../src/protocol.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract testProtocol is Test {
    DeployProtocol deployer;
    Protocol protocol;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    address public USER = makeAddr("USER");
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant STARTING_PROTOCOL_BALANCE = 1000 ether;
    uint256 public constant DEPOSIT = 2 ether;

    function setUp() public {
        deployer = new DeployProtocol();
        (protocol, tokenA, tokenB) = deployer.run();
        tokenA.mint(USER, STARTING_ERC20_BALANCE);
        tokenB.mint(USER, STARTING_ERC20_BALANCE);
        tokenA.mint(address(protocol), STARTING_PROTOCOL_BALANCE);
        tokenB.mint(address(protocol), STARTING_PROTOCOL_BALANCE);
    }

    function testUserCanDepositOnlyOneTypeOfToken() public {
        vm.startPrank(USER);
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        protocol.depositToken(address(tokenA), DEPOSIT);
        vm.expectRevert(Protocol.Protocol__InvalidCollateralToken.selector);
        protocol.depositToken(address(tokenB), DEPOSIT);
    }

    function testDepositTokenUpdatesBalance() public {
        vm.startPrank(USER);
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        protocol.depositToken(address(tokenA), DEPOSIT);
        uint256 deposit = protocol.getDeposits();
        assertEq(deposit, DEPOSIT);
    }

    function testOverCollateral() public {
        vm.startPrank(USER);
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        tokenB.approve(address(protocol), STARTING_ERC20_BALANCE);
        vm.expectRevert(Protocol.protocol__overCollateralNotGiven.selector);
        protocol.borrowToken(address(tokenA), address(tokenB), DEPOSIT, DEPOSIT);
    }

    function testWithdraw() public {
        vm.startPrank(USER);
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        protocol.depositToken(address(tokenA), DEPOSIT);
        protocol.withdraw(1 ether);
        assertEq(protocol.getDeposits(), 1 ether);
        vm.expectRevert(Protocol.protocol__InsufficientFunds.selector);
        protocol.withdraw(6 ether);
    }

    function testLiquidate() public {
        vm.startPrank(USER);
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        protocol.borrowToken(address(tokenA), address(tokenB), 5 ether, 1 ether);
        vm.expectRevert(Protocol.Protocol__SufficientCollateralProvided.selector);
        protocol.liquidate(USER);
    }

    function testcheckIfUserCanDoMultipleDepositsAndPartialWithdrawl() public {
        vm.startPrank(USER);
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        protocol.depositToken(address(tokenA), DEPOSIT);
        protocol.depositToken(address(tokenA), DEPOSIT);
        protocol.withdraw(3 ether);
        assertEq(protocol.getDeposits(), 1 ether);
    }

    function testLPEarnsInterest() public {
        vm.startPrank(USER);
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        vm.warp(1);
        protocol.depositToken(address(tokenA), DEPOSIT);
        vm.warp(1280000);
        protocol.depositToken(address(tokenA), DEPOSIT);
        uint256 balance = protocol.getDeposits();
        assert(balance > 4 ether);
    }
}
