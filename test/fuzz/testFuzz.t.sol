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
    uint256 public constant STARTING_ERC20_BALANCE = 100000 ether;
    uint256 public constant STARTING_PROTOCOL_BALANCE = 100000 ether;
    uint256 public constant DEPOSIT = 2 ether;

    function setUp() public {
        deployer = new DeployProtocol();
        (protocol, tokenA, tokenB) = deployer.run();
        tokenA.mint(USER, STARTING_ERC20_BALANCE);
        tokenB.mint(USER, STARTING_ERC20_BALANCE);
        tokenA.mint(address(protocol), STARTING_PROTOCOL_BALANCE);
        tokenB.mint(address(protocol), STARTING_PROTOCOL_BALANCE);
    }

    function testDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount < 10000 ether); // Prevent invalid values
        vm.startPrank(USER);
        uint256 initialBalance = protocol.getDeposits();
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        protocol.depositToken(address(tokenA), amount);
        assertEq(protocol.getDeposits(), initialBalance + amount);
        vm.stopPrank();
    }

    function testWithdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount < 10000 ether);
        vm.startPrank(USER);
        tokenA.approve(address(protocol), STARTING_ERC20_BALANCE);
        protocol.depositToken(address(tokenA), amount);
        protocol.withdraw(amount / 2);
    }

    function testBorrowAndRepay(uint256 borrowAmount, uint256 depositAmount) public {
        vm.assume(depositAmount > borrowAmount);
        vm.assume(depositAmount > 0 && depositAmount < 100000 ether);
        vm.startPrank(USER);
        tokenB.approve(address(protocol), type(uint256).max);
        protocol.borrowToken(address(tokenB), address(tokenA), depositAmount, borrowAmount);
        protocol.repay(borrowAmount / 2, address(tokenB));
    }
}
