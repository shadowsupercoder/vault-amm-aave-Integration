// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IStrategy {
    function execute(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function withdrawAll() external returns (uint256);
    function getBalance() external view returns (uint256);
}
