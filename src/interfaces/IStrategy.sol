// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IStrategy {
    function execute(bytes calldata params) external;
    function withdraw(bytes calldata params) external;
    function withdrawAll() external returns (uint256);
    function getBalance() external view returns (uint256);
}
