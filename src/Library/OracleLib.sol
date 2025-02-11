// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__stalePrice();

    uint256 private constant timeout = 3 hours;

    function stalePriceCheck(AggregatorV3Interface PriceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            PriceFeed.latestRoundData();
        uint256 secondSince = block.timestamp - updatedAt;
        if (secondSince > timeout) revert OracleLib__stalePrice();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
