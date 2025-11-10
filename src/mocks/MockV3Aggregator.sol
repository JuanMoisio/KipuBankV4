// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockV3Aggregator {
    int256 private _answer;
    uint8  public immutable decimals;

    constructor(uint8 _decimals, int256 initialAnswer) {
        decimals = _decimals;
        _answer  = initialAnswer;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, _answer, 0, 0, 0);
    }

    function updateAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }
}
