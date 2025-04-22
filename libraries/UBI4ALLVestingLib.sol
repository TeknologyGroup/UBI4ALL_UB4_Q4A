// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library UBI4ALLVestingLib {
    using SafeMath for uint256;

    struct VestingSchedule {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 duration;
        uint256 cliffDuration;
        bool isRevocable;
        bool isRevoked;
        uint256 lastReleaseTime;
    }

    function calculateReleasableAmount(
        VestingSchedule storage schedule
    ) internal view returns (uint256) {
        if (block.timestamp < schedule.startTime.add(schedule.cliffDuration)) {
            return 0;
        }

        if (block.timestamp >= schedule.startTime.add(schedule.duration)) {
            return schedule.totalAmount.sub(schedule.releasedAmount);
        }

        uint256 timeFromStart = block.timestamp.sub(schedule.startTime);
        uint256 vestedAmount = schedule.totalAmount
            .mul(timeFromStart)
            .div(schedule.duration);
            
        return vestedAmount.sub(schedule.releasedAmount);
    }
}