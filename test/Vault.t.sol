// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../src/Vault.sol";
import "../src/mock/MockERC20.sol";
// import "forge-std/console.sol";

contract VaultDepositWithdrawTest is Test {
    Vault vault;
    MockERC20 token;

    address owner = address(0x123);
    address user1 = address(0x456);
    address user2 = address(0x789);

    function setUp() public {
        // Deploy the mock token
        token = new MockERC20();
        token.initialize("MockToken", "MTK");

        // Deploy the vault contract with the mock token
        vm.prank(owner);
        vault = new Vault(address(token));

        // Distribute some tokens to users
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);
    }

    /*
        Tests the deposit function to ensure that users receive the correct amount
        of shares based on the amount deposited.
        Checks if the vault's token balance and the user's share balance are updated correctly.
     */
    function testDeposit() public {
        uint256 depositAmount = 100 ether;

        // User1 approves and deposits into the vault
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // Check that shares were minted correctly
        uint256 expectedShares = depositAmount;
        assertEq(vault.balanceOf(user1), expectedShares);
        assertEq(vault.totalSupply(), expectedShares);

        // Check the token balance of the vault
        assertEq(token.balanceOf(address(vault)), depositAmount);
        vm.stopPrank();
    }

    /*
        Tests the withdraw function to ensure that users can withdraw their
        tokens based on their shares.
        Verifies that the token balance of the vault decreases, and the user's
        balance increases after withdrawal.
     */
    function testWithdraw() public {
        uint256 depositAmount = 200 ether;

        // User1 deposits tokens into the vault
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        uint256 sharesMinted = vault.balanceOf(user1);
        assertEq(sharesMinted, depositAmount);

        // User1 withdraws their shares
        vault.withdraw(sharesMinted);

        // Check that the vault's balance is zero
        assertEq(token.balanceOf(address(vault)), 0);

        // Check that user1 received their tokens back
        assertEq(token.balanceOf(user1), 1000 ether);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.totalSupply(), 0);

        vm.stopPrank();
    }

    /*
        Tests the scenario where multiple users deposit and withdraw sequentially.
        Ensures that the vault correctly handles deposits and withdrawals when it
        already has a balance.
        Verifies that the shares are correctly distributed among users based
        on the vault's total balance.
    */
    function testDepositAndWithdrawWithExistingBalance() public {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 200 ether;

        // User1 deposits first
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount1);
        vault.deposit(depositAmount1);
        vm.stopPrank();

        // User2 deposits second
        vm.startPrank(user2);
        token.approve(address(vault), depositAmount2);
        vault.deposit(depositAmount2);
        vm.stopPrank();

        // Check the total supply and user balances
        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, depositAmount1 + depositAmount2);

        uint256 user1Shares = vault.balanceOf(user1);
        uint256 user2Shares = vault.balanceOf(user2);

        // User1 withdraws
        vm.startPrank(user1);
        vault.withdraw(user1Shares);
        assertEq(token.balanceOf(user1), 1000 ether);
        vm.stopPrank();

        // User2 withdraws
        vm.startPrank(user2);
        vault.withdraw(user2Shares);
        assertEq(token.balanceOf(user2), 1000 ether);
        vm.stopPrank();

        // Check the vault's balance and total supply
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(vault.totalSupply(), 0);
    }

    // Test 1: Partial Withdrawal
    function testPartialWithdraw() public {
        uint256 depositAmount = 200 ether;

        // User deposits tokens
        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // User withdraws half of their shares
        uint256 shares = vault.balanceOf(user1);
        uint256 partialShares = shares / 2;
        vault.withdraw(partialShares);

        // Check remaining shares and balance
        assertEq(vault.balanceOf(user1), shares - partialShares);
        assertEq(token.balanceOf(user1), 900 ether);
        vm.stopPrank();
    }

    // Test 2: Prevent Zero Deposit
    function testZeroDeposit() public {
        vm.startPrank(user1);
        token.approve(address(vault), 0);
        vm.expectRevert("Invalid amount");
        vault.deposit(0);
        vm.stopPrank();
    }

    // Test 3: Prevent Zero Withdraw
    function testZeroWithdraw() public {
        vm.startPrank(user1);
        vm.expectRevert("Invalid share amount");
        vault.withdraw(0);
        vm.stopPrank();
    }

    // Test 5: Over-withdrawal Prevention
    function testOverWithdraw() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user1);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        uint256 userShares = vault.balanceOf(user1);
        vm.expectRevert("Insufficient shares");
        vault.withdraw(userShares + 1);
        vm.stopPrank();
    }

    function testDepositWithInsufficientAllowance() public {
        vm.startPrank(user1);
        uint256 depositAmount = 100 ether;

        // User tries to deposit without approving enough tokens
        token.approve(address(vault), 50 ether); // Approve less than the deposit amount

        // Expect a revert with the custom error
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(vault),
                50 ether,
                depositAmount
            )
        );
        vault.deposit(depositAmount);
        vm.stopPrank();
    }

    function testWithdrawMoreThanBalance() public {
        vm.startPrank(user1);
        uint256 depositAmount = 100 ether;

        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        uint256 userShares = vault.balanceOf(user1);
        vm.expectRevert("Insufficient shares");
        vault.withdraw(userShares + 1); // Attempt to withdraw more than available shares
        vm.stopPrank();
    }
    function testDepositAfterWithdraw() public {
        vm.startPrank(user1);
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 50 ether;

        token.approve(address(vault), depositAmount1);
        vault.deposit(depositAmount1);

        uint256 userShares = vault.balanceOf(user1);
        vault.withdraw(userShares);

        // User should be able to deposit again after withdrawing
        token.approve(address(vault), depositAmount2);
        vault.deposit(depositAmount2);

        assertEq(vault.balanceOf(user1), depositAmount2);
        vm.stopPrank();
    }
    function testWithdrawAfterFullSupplyBurned() public {
        vm.startPrank(user1);
        uint256 depositAmount = 100 ether;

        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        uint256 userShares = vault.balanceOf(user1);
        vault.withdraw(userShares); // Withdraw all shares

        // Now, total supply should be zero
        assertEq(vault.totalSupply(), 0);

        // Attempt to withdraw again should fail
        vm.expectRevert("Insufficient shares");
        vault.withdraw(1);

        vm.stopPrank();
    }
    function testMultipleDepositsAndWithdrawals() public {
        vm.startPrank(user1);
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 50 ether;

        token.approve(address(vault), depositAmount1);
        vault.deposit(depositAmount1);

        token.approve(address(vault), depositAmount2);
        vault.deposit(depositAmount2);

        uint256 totalShares = vault.balanceOf(user1);
        assertEq(totalShares, depositAmount1 + depositAmount2);

        // Withdraw part of the shares
        vault.withdraw(depositAmount1);

        // Ensure the balance is updated correctly
        uint256 remainingShares = vault.balanceOf(user1);
        assertEq(remainingShares, depositAmount2);

        vm.stopPrank();
    }
}
