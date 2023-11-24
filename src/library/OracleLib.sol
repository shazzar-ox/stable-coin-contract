// SPDX-License-Identifier: MIT

pragma solidity ~0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {MockV3Aggregator} from "../../test/mock/MockV3Aggregator.sol";

/**
 * @title OracleLib
 * @author Mayowa Abikoye
 * @notice This librabry is used to check the chainlink oracle for stale data...
 * if a price is stale the function will rever and render the dscengine unusable.. this is by design..
 * we want the dscengine to freeae if proces become stale...
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
