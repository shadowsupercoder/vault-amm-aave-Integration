// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library DiamondStorage {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.storage");

    struct StrategyData {
        address currentStrategy;
        mapping(address => bool) strategies;
        mapping(address => uint256) allocations; // Strategy-specific allocations
        address[] strategyList; // List of all strategies
    }

    function strategyStorage() internal pure returns (StrategyData storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }
}
