//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Protocol} from "../src/protocol.sol";
import {MockV3Aggregator} from "../test/mocks/mockV3Aggregator.sol";

contract DeployProtocol is Script {
    uint8 constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE_A = 2000e8;
    int256 public constant INITIAL_PRICE_B = 6000e8;

    function run() external returns (Protocol protocl, ERC20Mock tokenA, ERC20Mock tokenB) {
        vm.startBroadcast();
        MockV3Aggregator mockPriceFeedA = new MockV3Aggregator(DECIMALS, INITIAL_PRICE_A);
        MockV3Aggregator mockPriceFeedB = new MockV3Aggregator(DECIMALS, INITIAL_PRICE_B);
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        Protocol protocol =
            new Protocol(address(tokenA), address(tokenB), address(mockPriceFeedA), address(mockPriceFeedB));
        vm.stopBroadcast();
        return (protocol, tokenA, tokenB);
    }
}
