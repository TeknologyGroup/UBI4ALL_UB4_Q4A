// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/UBI4ALLVestingLib.sol";

contract UBI4ALLVesting is ReentrancyGuard, Ownable, Pausable {
    using UBI4ALLVestingLib for UBI4ALLVestingLib.VestingSchedule;

    // Constants
    uint256 public constant VESTING_DURATION = 10 * 365 days; // 10 years
    uint256 public constant VESTING_PERIODS = 120; // Monthly releases

    // State variables
    IERC20 public immutable ubi4allToken;
    mapping(address => UBI4ALLVestingLib.VestingSchedule) public vestingSchedules;
    uint256 public totalVested;
    uint256 public immutable vestingStartTime;

    // Events
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary, uint256 amount);

    constructor(address _ubi4allToken, address _initialOwner) Ownable(_initialOwner) {
        require(_ubi4allToken != address(0), "Invalid token");
        ubi4allToken = IERC20(_ubi4allToken);
        vestingStartTime = block.timestamp;
    }

    function createVesting(address beneficiary, uint256 amount) external onlyOwner whenNotPaused {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be > 0");
        require(vestingSchedules[beneficiary].totalAmount == 0, "Vesting already exists");

        UBI4ALLVestingLib.VestingSchedule memory schedule = UBI4ALLVestingLib.VestingSchedule({
            totalAmount: amount,
            startTime: block.timestamp,
            cliffDuration: 0, // No cliff for UBI4ALL
            duration: VESTING_DURATION,
            releasedAmount: 0,
            lastReleaseTime: block.timestamp,
            isRevocable: false,
            isRevoked: false
        });

        vestingSchedules[beneficiary] = schedule;
        totalVested += amount;

        require(ubi4allToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit VestingScheduleCreated(beneficiary, amount);
    }

    function release(address beneficiary) external nonReentrant whenNotPaused {
        UBI4ALLVestingLib.VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(!schedule.isRevoked, "Schedule revoked");

        uint256 releasableAmount = schedule.calculateReleasableAmount();
        require(releasableAmount > 0, "No tokens to release");

        schedule.releasedAmount += releasableAmount;
        schedule.lastReleaseTime = block.timestamp;

        require(ubi4allToken.transfer(beneficiary, releasableAmount), "Transfer failed");
        emit TokensReleased(beneficiary, releasableAmount);
    }

    function revoke(address beneficiary) external onlyOwner whenNotPaused {
        UBI4ALLVestingLib.VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "No vesting schedule");
        require(schedule.isRevocable, "Schedule not revocable");
        require(!schedule.isRevoked, "Schedule already revoked");

        uint256 unreleased = schedule.totalAmount - schedule.releasedAmount;
        schedule.isRevoked = true;
        totalVested -= unreleased;

        require(ubi4allToken.transfer(msg.sender, unreleased), "Transfer failed");
        emit VestingRevoked(beneficiary, unreleased);
    }

    // View functions
    function getVestingSchedule(address beneficiary) external view returns (UBI4ALLVestingLib.VestingSchedule memory) {
        return vestingSchedules[beneficiary];
    }

    function getReleasableAmount(address beneficiary) external view returns (uint256) {
        return vestingSchedules[beneficiary].calculateReleasableAmount();
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}