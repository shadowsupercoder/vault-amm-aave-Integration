// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IStrategy {
    function execute(uint256 amount) external;
}
