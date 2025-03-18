//SPDX-License-Identitifer: MIT
pragma solidity 0.8.24;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Protocol is ReentrancyGuard {
    // struct to keep track of token price, deposits, borrows
    error protocol__TokenNotSupported();
    error protocol__InsufficientFunds();
    error protocol__overCollateralNotGiven();
    error Protocol__InvalidCollateralToken();
    error Protocol__InvalidBorrowingToken();
    error Protocol__SufficientCollateralProvided();

    struct tokenData {
        uint256 lendingInterestRate;
        uint256 borrowingInterestRate;
        uint256 tokenInContract;
        address priceFeedAddress;
    }

    struct userData {
        uint256 amountDeposited;
        uint256 amountBorrowed;
        uint256 interestEarned;
        address depositTokenAddress;
        address borrowTokenAddress;
        uint256 lastTimeOfDeposit;
        uint256 lastTimeOfBorrow;
    }

    IERC20 tokenA;
    IERC20 tokenB;

    mapping(address tokenAddress => tokenData data) public reserves;
    mapping(address user => userData data) public userAccount; // keep track of user profile

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);

    modifier ValidTokenAddress(address tokenAddress) {
        if (reserves[tokenAddress].priceFeedAddress == address(0)) {
            revert protocol__TokenNotSupported();
        }
        if (tokenAddress != address(tokenA) && tokenAddress != address(tokenB)) {
            revert protocol__TokenNotSupported();
        }
        _;
    }

    constructor(address _tokenA, address _tokenB, address priceFeedA, address priceFeedB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        reserves[address(tokenA)] = tokenData({
            lendingInterestRate: 5,
            borrowingInterestRate: 10,
            tokenInContract: 0,
            priceFeedAddress: priceFeedA
        });

        reserves[address(tokenB)] = tokenData({
            lendingInterestRate: 3,
            borrowingInterestRate: 9,
            tokenInContract: 0,
            priceFeedAddress: priceFeedB
        });
    }
    //DEPOSIT

    function depositToken(address tokenAddress, uint256 amount) public nonReentrant ValidTokenAddress(tokenAddress) {
        //checks
        require(amount > 0, "cant deposit 0 token");
        // If user is depositing for the first time, set their collateral type
        if (userAccount[msg.sender].depositTokenAddress == address(0)) {
            userAccount[msg.sender].depositTokenAddress = tokenAddress;
            userAccount[msg.sender].borrowTokenAddress =
                (tokenAddress == address(tokenA)) ? address(tokenB) : address(tokenA);
        } else {
            // Ensure they can only deposit one type of token
            if (userAccount[msg.sender].depositTokenAddress != tokenAddress) {
                revert Protocol__InvalidCollateralToken();
            }
        }
        // effects
        uint256 amountToAdd = calculateInterestOnDeposit(tokenAddress, msg.sender);
        userAccount[msg.sender].amountDeposited += amount + amountToAdd;
        reserves[tokenAddress].tokenInContract += amount - amountToAdd;
        userAccount[msg.sender].lastTimeOfDeposit = block.timestamp;
        userAccount[msg.sender].interestEarned += amountToAdd;
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
    ) external ValidTokenAddress(borrowTokenAddress) ValidTokenAddress(depositTokenAddress) {
        if (depositTokenAddress == borrowTokenAddress) {
            revert();
        }
        if (userAccount[msg.sender].borrowTokenAddress == address(0)) {
            userAccount[msg.sender].borrowTokenAddress = borrowTokenAddress;
            userAccount[msg.sender].depositTokenAddress = depositTokenAddress;
        } else {
            // Ensure they can only borrow one type of token
            if (userAccount[msg.sender].borrowTokenAddress != borrowTokenAddress) {
                revert Protocol__InvalidBorrowingToken();
            }
        }
        // checks
        if (borrowAmount > IERC20(borrowTokenAddress).balanceOf(address(this))) {
            revert protocol__InsufficientFunds();
        }
        // check for overCollateralamount
        if (!checkOverCollateral(msg.sender, depositAmount, borrowAmount)) {
            revert protocol__overCollateralNotGiven();
        }
        // effects
        uint256 interestOnBorrowed = calculateInterestOnBorrow(borrowTokenAddress, msg.sender);
        depositToken(depositTokenAddress, depositAmount);
        userAccount[msg.sender].amountBorrowed += borrowAmount + interestOnBorrowed;
        reserves[borrowTokenAddress].tokenInContract += borrowAmount;
        userAccount[msg.sender].lastTimeOfBorrow = block.timestamp;
        // interactions
        IERC20(borrowTokenAddress).transfer(msg.sender, borrowAmount);
    }
    //WITHDRAW (user should get amountDeposited at the time of calling this function + interest earned)

    function withdraw(uint256 amount) public {
        // check if this breaks overcollateral
        if (amount > userAccount[msg.sender].amountDeposited) {
            revert protocol__InsufficientFunds();
        }
        address withdrawTokenAddress = userAccount[msg.sender].depositTokenAddress;
        uint256 netDeposit = userAccount[msg.sender].amountDeposited - amount;
        uint256 depositValueInUSD = ((getTokenPrice(userAccount[msg.sender].depositTokenAddress)) * netDeposit) / 1e8;
        uint256 borrowedValueInUSD = (
            (getTokenPrice(userAccount[msg.sender].borrowTokenAddress)) * (userAccount[msg.sender].amountBorrowed)
        ) / 1e8;
        if ((depositValueInUSD * 100) >= (borrowedValueInUSD * 150)) {
            IERC20(withdrawTokenAddress).transfer(msg.sender, amount);
        }
        uint256 interest = calculateInterestOnDeposit(withdrawTokenAddress, msg.sender);
        userAccount[msg.sender].amountDeposited -= amount;
        reserves[withdrawTokenAddress].tokenInContract -= (interest + amount);
        userAccount[msg.sender].lastTimeOfDeposit = block.timestamp;
        IERC20(withdrawTokenAddress).transfer(msg.sender, amount + interest);
    }
    //REPAY BORROWED ASSETS

    function repay(uint256 amount, address tokenAddress) external ValidTokenAddress(tokenAddress) {
        uint256 interestOnBorrow = calculateInterestOnBorrow(tokenAddress, msg.sender);
        userAccount[msg.sender].amountBorrowed += interestOnBorrow;
        userAccount[msg.sender].amountBorrowed -= amount;
        reserves[tokenAddress].tokenInContract += amount;
        userAccount[msg.sender].lastTimeOfBorrow = block.timestamp;
        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
    }

    function liquidate(address user) public {
        if (!checkOverCollateral(user, 0, 0)) {
            userAccount[user].amountBorrowed = 0;
            userAccount[user].amountDeposited = 0;
        } else {
            revert Protocol__SufficientCollateralProvided();
        }
    }

    function checkOverCollateral(address user, uint256 depositAmount, uint256 borrowAmount)
        internal
        view
        returns (bool)
    {
        uint256 netDeposit = userAccount[user].amountDeposited + depositAmount;
        uint256 netBorrowed = userAccount[user].amountBorrowed + borrowAmount;
        uint256 depositValueInUSD = ((getTokenPrice(userAccount[user].depositTokenAddress)) * netDeposit) / 1e8;
        uint256 borrowedValueInUSD = ((getTokenPrice(userAccount[user].borrowTokenAddress)) * netBorrowed) / 1e8;
        return (depositValueInUSD * 100) >= (borrowedValueInUSD * 150);
    }

    function getTokenPrice(address tokenAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(reserves[tokenAddress].priceFeedAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function calculateInterestOnDeposit(address token, address user) public view returns (uint256) {
        uint256 amount = userAccount[user].amountDeposited;
        uint256 timeElapsed = block.timestamp - userAccount[user].lastTimeOfDeposit;
        uint256 interestRatePerSecond = ((reserves[token].lendingInterestRate) * 1e18) / 31536000;
        uint256 interest = (amount * interestRatePerSecond * timeElapsed) / 1e18;
        return interest;
    }

    function calculateInterestOnBorrow(address token, address user) public view returns (uint256) {
        uint256 amount = userAccount[user].amountBorrowed;
        uint256 timeElapsed = block.timestamp - userAccount[user].lastTimeOfBorrow;
        uint256 interestRatePerSecond = ((reserves[token].borrowingInterestRate) * 1e18) / 31536000;
        uint256 interest = (amount * interestRatePerSecond * timeElapsed) / 1e18;
        return interest;
    }

    function getDeposits() external view returns (uint256) {
        return userAccount[msg.sender].amountDeposited;
    }

    function getReserve() external view returns (uint256, uint256) {
        return (reserves[address(tokenA)].tokenInContract, reserves[address(tokenB)].tokenInContract);
    }
}
