// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MockERC20 is ERC20Upgradeable {
    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        _mint(msg.sender, 1_000_000 * 10 ** decimals()); // Mint 1,000,000 tokens to deployer
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
