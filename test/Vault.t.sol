// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MKT") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}

contract VaultTest is Test {
    Vault vault;
    MockERC20 token;

    address user = address(0x123);

    function setUp() public {
        token = new MockERC20();
        vault = new Vault(IERC20(address(token)));
        token.approve(address(vault), type(uint256).max);
        vm.deal(user, 100 ether);
    }

    function testDeposit() public {
        uint256 depositAmount = 1000 ether;
        token.transfer(user, depositAmount);
        vm.startPrank(user);

        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        uint256 userShares = vault.shares(user);
        assertEq(userShares, depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 1000 ether;
        token.transfer(user, depositAmount);
        vm.startPrank(user);

        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        uint256 userShares = vault.shares(user);
        vault.withdraw(userShares);

        uint256 userBalance = token.balanceOf(user);
        assertEq(userBalance, depositAmount);
    }
}
