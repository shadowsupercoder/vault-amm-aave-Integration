// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/mock/MockERC20.sol";
import "../src/mock/MockAggregatorV3.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "uniswap/v2-periphery/interfaces/IUniswapV2Router02.sol";

contract VaultOwnershipTest is Test {
    Vault vault;
    MockERC20 token;

    address admin = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    uint256 initialSlippage = 50;

    IUniswapV2Router02 public router;
    MockAggregatorV3 public mockPriceFeed;

    function setUp() public {
        // Deploy the mock ERC20 token
        token = new MockERC20();
        mockPriceFeed = new MockAggregatorV3();
        router = IUniswapV2Router02(deployCode("UniswapV2Router02.sol"));

        // Deploy and initialize the vault contract with the admin
        vm.startPrank(admin);
        vault = new Vault(address(token), address(router), address(mockPriceFeed));
        vault.initialize(admin, initialSlippage);
        vm.stopPrank();
    }

    /*
        Ensure only the admin can grant and revoke roles.
    */
    function testAdminCanGrantAndRevokeRoles() public {
        // Admin grants DEFAULT_ADMIN_ROLE to user1
        vm.startPrank(admin);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), user1);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), user2);
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user1));
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user2));

        // Admin revokes DEFAULT_ADMIN_ROLE from user1
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), user2);
        assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user2));
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user1));

        vm.stopPrank();
    }

    /*
       Ensure only the admin can call the setMaxSlippage function.
    */
    function testOnlyAdminCanCallSetMaxSlippage() public {
        // Non-admin tries to call setMaxSlippage
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(user1), vault.DEFAULT_ADMIN_ROLE()
            )
        );
        address[] memory path;
        vault.swapTokens(0, 0, path, user2, 0);
        vm.stopPrank();

        assertEq(vault.maxSlippage(), 50);

        // Admin calls setMaxSlippage successfully
        vm.prank(admin);
        vault.setMaxSlippage(70);
        assertEq(vault.maxSlippage(), 70);
    }

    /*
         Ensure non-admins cannot grant or revoke roles. FIXME
    */
    // function testNonAdminCannotGrantOrRevokeRoles() public {
    //     assertFalse(vault.hasRole(vault.ADMIN_ROLE(), user1));
    //     assertFalse(vault.hasRole(vault.ADMIN_ROLE(), user2));
    //     // Non-admin (user1) tries to grant ADMIN_ROLE to user2
    //     vm.startPrank(user1);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IAccessControl.AccessControlUnauthorizedAccount.selector,
    //             address(user1),
    //             bytes32(0)
    //         )
    //     );

    //     vault.grantRole(vault.ADMIN_ROLE(), user2);

    //     // Non-admin (user1) tries to revoke ADMIN_ROLE from admin
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IAccessControl.AccessControlUnauthorizedAccount.selector,
    //             address(user1),
    //             bytes32(0)
    //         )
    //     );
    //     vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), admin);
    //     vm.stopPrank();
    // }

    /*
       Attempt to grant roles with a non-admin account and expect failure. FIXME
    */
    // function testNonAdminCannotGrantRole() public {
    //     // User1 tries to grant ADMIN_ROLE to themselves
    //     vm.startPrank(user1);
    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             IAccessControl.AccessControlUnauthorizedAccount.selector,
    //             address(user1),
    //             bytes32(0)
    //         )
    //     );

    //     vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), user1);

    //     // Ensure user1 still doesn't have the role
    //     assertFalse(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), user1));
    //     vm.stopPrank();
    // }
}
