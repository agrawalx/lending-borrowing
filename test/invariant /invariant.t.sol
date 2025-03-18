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
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant STARTING_PROTOCOL_BALANCE = 100 ether;
    uint256 public constant DEPOSIT = 2 ether;

    function setUp() public {
        deployer = new DeployProtocol();
        (protocol, tokenA, tokenB) = deployer.run();
        tokenA.mint(USER, STARTING_ERC20_BALANCE);
        tokenB.mint(USER, STARTING_ERC20_BALANCE);
    }

    function invariant_DepositedMoreThanBorrowed() public {
        (uint256 amountA, uint256 amountB) = protocol.getReserve();
        uint256 costA = protocol.getTokenPrice(address(tokenA));
        uint256 costB = protocol.getTokenPrice(address(tokenB));
        assert((costA * amountA) * 100 >= (costB * amountB) * 150);
    }
}
