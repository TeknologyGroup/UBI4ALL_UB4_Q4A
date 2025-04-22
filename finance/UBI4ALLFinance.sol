// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "core/UBI4ALLToken.sol";
import "../interfaces/IUBI4ALLOracle.sol";

contract UBI4ALLFinance is ReentrancyGuard, Pausable, Ownable {
    using SafeMath for uint256;

    // Structs
    struct StakingPool {
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 minimumStakingPeriod;
        uint256 earlyWithdrawalFee;
        uint256 accumulatedFees;
    }

    struct Loan {
        uint256 amount;
        uint256 interestRate;
        uint256 duration;
        uint256 startTime;
        uint256 collateralAmount;
        bool isActive;
        address borrower;
    }

    // Constants
    uint256 private constant PRECISION = 10000;
    uint256 public constant STAKING_FEE = 50; // 0.5%
    uint256 public constant LOAN_INTEREST_RATE = 200; // 2% annual
    uint256 public constant MAX_LOAN_AMOUNT = 1000 * 10**18; // 1000 UB4
    uint256 public constant MIN_COLLATERAL_RATIO = 15000; // 150%

    // Contract references
    UBI4ALLToken public immutable ubi4allToken;
    IUBI4ALLOracle public immutable oracle;

    // State variables
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lastStakeTime;
    mapping(address => Loan[]) public userLoans;
    StakingPool public stakingPool;
    uint256 public totalValueLocked;
    uint256 public totalLoaned;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 fee);
    event RewardPaid(address indexed user, uint256 reward);
    event LoanIssued(
        address indexed borrower, 
        uint256 loanId, 
        uint256 amount, 
        uint256 collateral
    );
    event LoanRepaid(
        address indexed borrower, 
        uint256 loanId, 
        uint256 amount, 
        uint256 interest
    );
    event EmergencyAction(string action, string reason);

    constructor(
        address _ubi4allToken,
        address _oracle,
        address initialOwner
    ) Ownable(initialOwner) {
        require(_ubi4allToken != address(0), "Invalid UB4 token");
        require(_oracle != address(0), "Invalid oracle");

        ubi4allToken = UBI4ALLToken(_ubi4allToken);
        oracle = IUBI4ALLOracle(_oracle);

        // Initialize staking pool
        stakingPool = StakingPool({
            totalStaked: 0,
            rewardRate: 100, // 1% annual reward rate (adjustable)
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            minimumStakingPeriod: 30 days,
            earlyWithdrawalFee: 500, // 5%
            accumulatedFees: 0
        });
    }

    // Staking functions
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");
        _updateReward(msg.sender);

        stakedBalance[msg.sender] = stakedBalance[msg.sender].add(amount);
        stakingPool.totalStaked = stakingPool.totalStaked.add(amount);
        lastStakeTime[msg.sender] = block.timestamp;
        totalValueLocked = totalValueLocked.add(amount);

        require(ubi4allToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot withdraw 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient balance");

        _updateReward(msg.sender);

        uint256 fee = 0;
        if (block.timestamp < lastStakeTime[msg.sender].add(stakingPool.minimumStakingPeriod)) {
            fee = amount.mul(stakingPool.earlyWithdrawalFee).div(PRECISION);
            stakingPool.accumulatedFees = stakingPool.accumulatedFees.add(fee);
        }

        uint256 withdrawAmount = amount.sub(fee);
        stakedBalance[msg.sender] = stakedBalance[msg.sender].sub(amount);
        stakingPool.totalStaked = stakingPool.totalStaked.sub(amount);
        totalValueLocked = totalValueLocked.sub(amount);

        require(ubi4allToken.transfer(msg.sender, withdrawAmount), "Transfer failed");
        emit Unstaked(msg.sender, amount, fee);
    }

    function claimReward() external nonReentrant whenNotPaused {
        _updateReward(msg.sender);

        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        rewards[msg.sender] = 0;
        require(ubi4allToken.transfer(msg.sender, reward), "Transfer failed");

        emit RewardPaid(msg.sender, reward);
    }

    function rewardPerToken() public view returns (uint256) {
        if (stakingPool.totalStaked == 0) {
            return stakingPool.rewardPerTokenStored;
        }

        uint256 timeElapsed = block.timestamp.sub(stakingPool.lastUpdateTime);
        return stakingPool.rewardPerTokenStored.add(
            timeElapsed
                .mul(stakingPool.rewardRate)
                .mul(1e18)
                .div(stakingPool.totalStaked)
        );
    }

    function earned(address account) public view returns (uint256) {
        uint256 rewardDiff = rewardPerToken().sub(stakingPool.rewardPerTokenStored);
        return stakedBalance[account]
            .mul(rewardDiff)
            .div(1e18)
            .add(rewards[account]);
    }

    function _updateReward(address account) internal {
        stakingPool.rewardPerTokenStored = rewardPerToken();
        stakingPool.lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            rewards[account] = earned(account);
        }
    }

    // Loan functions
    function requestLoan(
        uint256 amount,
        uint256 duration,
        uint256 collateral
    ) external nonReentrant whenNotPaused {
        require(amount > 0 && amount <= MAX_LOAN_AMOUNT, "Invalid loan amount");
        require(duration > 0 && duration <= 365 days, "Invalid duration");
        require(collateral > 0, "Collateral required");

        // Check collateral value using oracle
        (uint256 price,, bool isValid) = oracle.getPrice(bytes32("EUR/USD"));
        require(isValid, "Invalid price");
        uint256 collateralValue = collateral.mul(price).div(1e8); // Price in USD with 8 decimals
        require(
            collateralValue >= amount.mul(MIN_COLLATERAL_RATIO).div(PRECISION),
            "Insufficient collateral"
        );

        require(ubi4allToken.transferFrom(msg.sender, address(this), collateral), "Collateral transfer failed");
        require(ubi4allToken.transfer(msg.sender, amount), "Loan transfer failed");

        Loan memory loan = Loan({
            amount: amount,
            interestRate: LOAN_INTEREST_RATE,
            duration: duration,
            startTime: block.timestamp,
            collateralAmount: collateral,
            isActive: true,
            borrower: msg.sender
        });

        userLoans[msg.sender].push(loan);
        totalLoaned = totalLoaned.add(amount);

        emit LoanIssued(msg.sender, userLoans[msg.sender].length - 1, amount, collateral);
    }

    function repayLoan(uint256 loanId) external nonReentrant whenNotPaused {
        require(loanId < userLoans[msg.sender].length, "Invalid loan");
        Loan storage loan = userLoans[msg.sender][loanId];
        require(loan.isActive, "Loan already repaid");
        require(loan.borrower == msg.sender, "Not borrower");

        uint256 interest = loan.amount
            .mul(LOAN_INTEREST_RATE)
            .mul(block.timestamp.sub(loan.startTime))
            .div(365 days)
            .div(PRECISION);
        uint256 totalRepay = loan.amount.add(interest);

        require(ubi4allToken.transferFrom(msg.sender, address(this), totalRepay), "Repay transfer failed");
        require(ubi4allToken.transfer(msg.sender, loan.collateralAmount), "Collateral return failed");

        loan.isActive = false;
        totalLoaned = totalLoaned.sub(loan.amount);

        emit LoanRepaid(msg.sender, loanId, loan.amount, interest);
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
        emit EmergencyAction("pause", "Emergency pause activated");
    }

    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyAction("unpause", "Emergency pause deactivated");
    }
}