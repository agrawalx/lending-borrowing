//SPDX-License-Identitifer: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract protocol is ReentrancyGuard {
    // struct to keep track of token price, deposits, borrows
    error protocol__TokenNotSupported();
    error protocol__InsufficientFunds();
    error protocol__overCollateralNotGiven();

    struct tokenData {
        uint256 lendingInterestRate;
        uint256 borrowingInterestRate;
        uint256 tokenDeposited;
        uint256 tokenBorrowed;
        address priceFeedAddress;
    }

    struct userData {
        uint256 amountDeposited;
        uint256 amountBorrowed;
        uint256 interestEarned;
    }

    mapping(address tokenAddress => tokenData data) public reserves;
    mapping(address user => mapping(address tokenAddress => userData data)) public userAccount; // keep track of user profile

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);

    modifier ValidTokenAddress(address tokenAddress) {
        if (reserves[tokenAddress].priceFeedAddress == address(0)) {
            revert protocol__TokenNotSupported();
        }
        _;
    }
    //DEPOSIT

    function depositToken(address tokenAddress, uint256 amount) external nonReentrant ValidTokenAddress(tokenAddress) {
        //checks
        require(amount > 0, "cant deposit 0 token");
        // effects
        userAccount[msg.sender][tokenAddress].amountDeposited += amount;
        reserves[tokenAddress].tokenDeposited += amount;
        // interaction
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, tokenAddress, amount);
    }
    //BORROW

    function borrowToken(
        address depositTokenAddress,
        address borrowTokenAddress,
        uint256 depositAmount,
        uint256 borrowAmount
    ) external nonReentrant ValidTokenAddress(borrowTokenAddress) ValidTokenAddress(depositTokenAddress) {
        // checks
        if (borrowAmount > IERC20(borrowTokenAddress).balanceOf(address(this))) {
            revert protocol__InsufficientFunds();
        }
        // check for overCollateralamount
        if (
            checkOverCollateral(depositTokenAddress, borrowTokenAddress, msg.sender, depositAmount, borrowAmount)
                == false
        ) {
            revert protocol__overCollateralNotGiven();
        }
        // effects
        userAccount[msg.sender][borrowTokenAddress].amountBorrowed += borrowAmount;
        userAccount[msg.sender][depositTokenAddress].amountDeposited += depositAmount;
        reserves[borrowTokenAddress].tokenBorrowed += borrowAmount;
        reserves[depositTokenAddress].tokenDeposited += depositAmount;
        // interactions
        IERC20(borrowTokenAddress).transfer(msg.sender, borrowAmount);
        IERC20(depositTokenAddress).transferFrom(msg.sender, address(this), depositAmount);
    }
    //WITHDRAW (user should get amountDeposited at the time of calling this function + interest earned)
    //REPAY BORROWED ASSETS

    function checkOverCollateral(
        address depositTokenAddress,
        address borrowtokenAddress,
        address user,
        uint256 depositAmount,
        uint256 borrowAmount
    ) internal view returns (bool) {
        uint256 netDeposit = userAccount[user][depositTokenAddress].amountDeposited + depositAmount;
        uint256 netBorrowed = userAccount[user][borrowtokenAddress].amountBorrowed + borrowAmount;
        uint256 depositValueInUSD = (getTokenPrice(depositTokenAddress)) * netDeposit;
        uint256 borrowedValueInUSD = (getTokenPrice(borrowtokenAddress)) * netBorrowed;
        return (depositValueInUSD * 100) >= (borrowedValueInUSD * 150);
    }

    function getTokenPrice(address tokenAddress) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(reserves[tokenAddress].priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }
}
